/**
 * Barramento de eventos em tempo real.
 *
 * Publicação: pg_notify('estoque_events', json). Assim, com N instâncias da API
 * atrás do balanceador, um evento gerado em qualquer uma chega a todos os
 * dashboards conectados — cada instância mantém UM cliente em LISTEN e repassa
 * aos seus streams SSE do mesmo tenant.
 *
 * O payload do NOTIFY é mínimo (tipo + ids). Quem recebe busca o detalhe pela API:
 * evita vazar dados entre perfis (operador não vê quantidade esperada) e respeita
 * o limite de 8 KB do NOTIFY.
 */
'use strict';

const { Client } = require('pg');
const config = require('../config');
const db = require('../db');
const log = require('../log');

const CHANNEL = 'estoque_events';
const streams = new Map(); // tenantId → Set<res>
let listener = null;
let reconnectTimer = null;

function deliver(event) {
    const set = streams.get(event.tenantId);
    if (!set) return;
    const frame = `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
    for (const res of set) res.write(frame);
}

async function startListener() {
    const client = new Client(
        config.pg.connectionString
            ? { connectionString: config.pg.connectionString, ssl: config.pg.ssl }
            : { host: config.pg.host, port: config.pg.port, database: config.pg.database,
                user: config.pg.user, password: config.pg.password, ssl: config.pg.ssl },
    );
    client.on('notification', (msg) => {
        try { deliver(JSON.parse(msg.payload)); } catch { /* payload malformado: ignora */ }
    });
    client.on('error', (err) => {
        log.warn('[Realtime] conexão LISTEN caiu — reconectando', { error: err.message });
        scheduleReconnect();
    });
    client.on('end', scheduleReconnect);
    await client.connect();
    await client.query(`LISTEN ${CHANNEL}`);
    listener = client;
    log.info('[Realtime] LISTEN ativo');
}

let stopping = false;

function scheduleReconnect() {
    if (stopping || reconnectTimer) return;
    listener = null;
    reconnectTimer = setTimeout(async () => {
        reconnectTimer = null;
        try { await startListener(); } catch (err) {
            log.warn('[Realtime] falha ao reconectar', { error: err.message });
            scheduleReconnect();
        }
    }, 3_000);
}

/**
 * Publica um evento para os dashboards do tenant.
 * @param {string} tenantId
 * @param {string} type  ex.: document.updated, scan.added, worker.heartbeat, sync.completed
 * @param {object} [data] ids e contadores — nunca quantidades esperadas
 */
function publish(tenantId, type, data = {}) {
    const payload = JSON.stringify({ tenantId, type, at: new Date().toISOString(), ...data });
    db.query('SELECT pg_notify($1, $2)', [CHANNEL, payload])
        .catch((err) => log.warn('[Realtime] pg_notify falhou', { error: err.message }));
}

/** Registra um response HTTP como stream SSE do tenant. */
function attach(tenantId, res) {
    res.set({
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'X-Accel-Buffering': 'no', // nginx: não bufferizar o stream
    });
    res.flushHeaders();
    res.write('retry: 5000\n\n');

    if (!streams.has(tenantId)) streams.set(tenantId, new Set());
    streams.get(tenantId).add(res);

    // Comentário a cada 25 s mantém proxies (Coolify/Traefik/nginx) com a conexão aberta.
    const ping = setInterval(() => res.write(': ping\n\n'), 25_000);
    res.on('close', () => {
        clearInterval(ping);
        const set = streams.get(tenantId);
        set?.delete(res);
        if (set?.size === 0) streams.delete(tenantId);
    });
}

async function stop() {
    stopping = true;
    clearTimeout(reconnectTimer);
    for (const set of streams.values()) for (const res of set) res.end();
    streams.clear();
    if (listener) await listener.end().catch(() => {});
}

module.exports = { startListener, publish, attach, stop };

'use strict';

const config = require('./config');
const log = require('./log');
const db = require('./db');
const bus = require('./realtime/bus');
const app = require('./app');

process.on('unhandledRejection', (reason) => {
    log.error('[App] promise rejeitada sem tratamento', { reason: reason instanceof Error ? reason.stack : String(reason) });
});

let server;

async function start() {
    await db.migrate();
    await bus.startListener();
    server = app.listen(config.port, () => log.info('[App] Coliseu Estoque API no ar', { port: config.port }));
    // SSE mantém conexões longas: o keep-alive do Node não pode derrubá-las antes do proxy.
    server.keepAliveTimeout = 65_000;
    server.headersTimeout = 66_000;
}

async function shutdown(signal) {
    log.info('[App] encerrando', { signal });
    setTimeout(() => process.exit(1), 10_000).unref();
    server?.close();
    await bus.stop();
    await db.pool.end().catch(() => {});
    process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

start().catch((err) => {
    log.error('[App] falha no startup', { error: err.message });
    process.exit(1);
});

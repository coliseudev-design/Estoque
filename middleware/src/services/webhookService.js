/**
 * webhookService.js — Envio de webhooks por empresa (P2-E).
 *
 * Quando o Worker confirma um pedido (status → synced ou error),
 * o middleware envia um POST para a URL configurada pela empresa.
 *
 * Segurança:
 *   - Payload assinado com HMAC-SHA256 usando o `secret` da empresa
 *   - Header `X-Coliseu-Signature: sha256=<hex>` para verificação
 *   - Timeout de 5s, 2 tentativas, sem bloqueio do fluxo principal
 *
 * @module services/webhookService
 */
'use strict';

const crypto = require('crypto');
const https = require('https');
const http = require('http');
const { pgQuery } = require('../db/postgres');
const logger = require('../config/logger');

/**
 * Assina o payload com HMAC-SHA256.
 * @param {string} secret
 * @param {string} body JSON string
 * @returns {string} sha256=<hex>
 */
function signPayload(secret, body) {
    const sig = crypto.createHmac('sha256', secret).update(body, 'utf8').digest('hex');
    return `sha256=${sig}`;
}

/**
 * Envia uma requisição HTTP/HTTPS POST com timeout.
 * @returns {Promise<number>} HTTP status code
 */
function httpPost(url, headers, body) {
    return new Promise((resolve, reject) => {
        const { hostname, port, pathname, protocol } = new URL(url);
        const lib = protocol === 'https:' ? https : http;

        const req = lib.request({
            hostname, port, path: pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body),
                ...headers,
            },
            timeout: 5000,
        }, (res) => {
            res.resume();
            resolve(res.statusCode);
        });

        req.on('error', reject);
        req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
        req.write(body);
        req.end();
    });
}

/**
 * Dispara webhooks configurados para uma empresa ao mudar status de pedido.
 * Executa em background (fire-and-forget) — não bloqueia o request principal.
 *
 * @param {string} companyId  UUID da empresa
 * @param {string} event      'order.confirmed' | 'order.error' | 'order.created'
 * @param {object} data       Dados do pedido
 */
async function dispatchWebhook(companyId, event, data) {
    try {
        const { rows } = await pgQuery(
            `SELECT url, secret FROM company_webhooks
             WHERE company_id = $1 AND active = TRUE AND $2 = ANY(events)`,
            [companyId, event]
        );

        if (!rows.length) return;

        const payload = JSON.stringify({
            event,
            companyId,
            timestamp: new Date().toISOString(),
            data,
        });

        for (const wh of rows) {
            const signature = signPayload(wh.secret, payload);

            // Fire-and-forget com 2 tentativas
            (async () => {
                for (let attempt = 1; attempt <= 2; attempt++) {
                    try {
                        const status = await httpPost(wh.url, {
                            'X-Coliseu-Signature': signature,
                            'X-Coliseu-Event': event,
                        }, payload);

                        if (status >= 200 && status < 300) {
                            logger.info('[Webhook] Entregue', { url: wh.url, event, status });
                            return;
                        }
                        logger.warn('[Webhook] Resposta não-2xx', { url: wh.url, status, attempt });
                    } catch (err) {
                        logger.warn('[Webhook] Falha na tentativa', { url: wh.url, attempt, error: err.message });
                    }
                    if (attempt < 2) await new Promise(r => setTimeout(r, 1500));
                }
                logger.error('[Webhook] Falha após 2 tentativas', { url: wh.url, event });
            })().catch(() => { });  // Isola erros
        }
    } catch (err) {
        logger.error('[Webhook] Erro ao buscar configuração', { companyId, error: err.message });
    }
}

module.exports = { dispatchWebhook };

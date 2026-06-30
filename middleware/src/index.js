/**
 * Entry point da aplicação — Coliseu Speed Force Middleware.
 *
 * Responsabilidades:
 * - Inicializar pool Firebird
 * - Subir o servidor HTTP
 * - Graceful shutdown ao receber SIGTERM/SIGINT
 * - Capturar erros globais não tratados (unhandledRejection / uncaughtException)
 *
 * A configuração do Express (rotas, middlewares) está em ./app.js
 * para permitir testes via supertest sem subir o servidor.
 */
'use strict';

const app = require('./app');
const config = require('./config/env');
const logger = require('./config/logger');
const { initPool, destroyPool } = require('./services/firebird.service');
const firebirdManager = require('./services/firebird.manager');
const { runMigrations, seedDefaultCompany } = require('./db/migrate');
const { client: redisClient } = require('./db/redis');


// ─────────────────────────────────────────────────────────────────────────────
// Handlers globais — evita crash silencioso por Promises não tratadas
//
// SEM estes handlers, qualquer `await` sem .catch() em uma Promise rejeitada
// mata o processo Node em versões >= 15. Com PM2 ele reinicia, mas sem PM2
// o serviço simplesmente some e retorna 502 / Gateway Timeout.
// ─────────────────────────────────────────────────────────────────────────────

process.on('unhandledRejection', (reason, promise) => {
    logger.error('[App] UNHANDLED REJECTION — Promise rejeitada sem .catch()', {
        reason: reason instanceof Error ? reason.message : String(reason),
        stack: reason instanceof Error ? reason.stack : undefined,
    });
    // NÃO faz process.exit() — permite que o PM2 / servidor continue vivo.
    // O healthcheck em /health vai detectar degradação e o PM2 pode reiniciar.
});

process.on('uncaughtException', (err) => {
    logger.error('[App] UNCAUGHT EXCEPTION — Erro síncrono não capturado', {
        error: err.message,
        stack: err.stack,
    });
    // uncaughtException deixa o processo em estado inconsistente:
    // saída controlada para o PM2 reiniciar de forma limpa.
    process.exit(1);
});


// ─────────────────────────────────────────────────────────────────────────────
// Startup
// ─────────────────────────────────────────────────────────────────────────────

let server;

async function start() {
    try {
        logger.info('[App] Iniciando Coliseu Speed Middleware...');
        logger.info('[App] Ambiente:', { env: config.nodeEnv });

        // Inicializa pool Firebird antes de aceitar requisições
        await initPool();

        // Migrations PostgreSQL — rodam sempre que PG estiver disponível,
        // independente do modo Firebird (FB_MOCK). PostgreSQL é necessário
        // apenas para companies, orders, etc. — não depende de Firebird.
        try {
            await runMigrations();
            await seedDefaultCompany();
        } catch (pgErr) {
            const isMock = process.env.FB_MOCK === 'true';
            const isAsync = process.env.SYNC_MODE === 'async';
            if (config.nodeEnv === 'production' && !isMock && !isAsync) {
                throw pgErr; // fatal em prod direct-mode
            }
            logger.warn('[App] PostgreSQL migrations falharam — middleware continua sem log de pedidos.', { error: pgErr.message });
        }

        server = app.listen(config.port, () => {
            logger.info(`[App] Servidor iniciado na porta ${config.port}`);
            logger.info(`[App] Health check disponível em: http://localhost:${config.port}/health`);
        });

        server.on('error', (err) => {
            logger.error('[App] Erro crítico no servidor HTTP', { error: err.message });
            process.exit(1);
        });

    } catch (err) {
        logger.error('[App] Falha crítica no startup', { error: err.message });
        process.exit(1);
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// Graceful Shutdown
// ─────────────────────────────────────────────────────────────────────────────

async function shutdown(signal) {
    logger.info(`[App] Recebido sinal ${signal}. Iniciando graceful shutdown...`);

    if (server) server.keepAliveTimeout = 0;

    server?.close(async () => {
        logger.info('[App] Servidor HTTP fechado.');
        await destroyPool();
        await firebirdManager.destroyAll();
        try { await redisClient.quit(); } catch (_) { }
        logger.info('[App] Pools Firebird (global + por empresa) e Redis fechados. Bye!');
        process.exit(0);
    });

    setTimeout(() => {
        logger.error('[App] Graceful shutdown excedeu 10s. Forçando saída.');
        process.exit(1);
    }, 10_000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

start();

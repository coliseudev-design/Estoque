'use strict';

const app = require('./app');
const config = require('./config/env');
const logger = require('./config/logger');
const db = require('./db/postgres');

async function startServer() {
    try {
        // Testa conexão ao banco antes de abrir portas
        const dbOk = await db.checkConnection();
        if (!dbOk) {
            logger.warn('[App] Banco de dados indisponível no boot. Servidor continuará iniciando para health-checks falharem graciosamente.');
        } else {
            // Executa migrations
            await db.runMigrations();
        }

        const server = app.listen(config.server.port, () => {
            logger.info(`[App] AutoCenter Middleware rodando na porta ${config.server.port} [${config.server.nodeEnv}]`);
        });

        // Graceful shutdown
        const shutdown = () => {
            logger.info('[App] Recebido sinal de parada. Fechando servidor...');
            server.close(async () => {
                logger.info('[App] Servidor HTTP fechado.');
                await db.pool.end();
                logger.info('[App] Conexão com PostgreSQL fechada.');
                process.exit(0);
            });

            // Força parada após 10s se demorar muito
            setTimeout(() => {
                logger.error('[App] Forçando encerramento após timeout.');
                process.exit(1);
            }, 10000).unref();
        };

        process.on('SIGTERM', shutdown);
        process.on('SIGINT', shutdown);

    } catch (err) {
        logger.error('[App] Falha crítica ao iniciar servidor', err);
        process.exit(1);
    }
}

startServer();

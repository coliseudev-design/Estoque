/**
 * ecosystem.config.js — Configuração PM2 para o middleware Coliseu Speed.
 *
 * Deploy na VPS:
 *   pm2 start ecosystem.config.js --env production
 *   pm2 save
 *   pm2 startup   <-- gera o comando para iniciar o PM2 no boot do sistema
 *
 * Comandos úteis:
 *   pm2 logs coliseu-middleware        -- ver logs em tempo real
 *   pm2 monit                          -- dashboard de memória/CPU
 *   pm2 restart coliseu-middleware     -- reinício manual
 *   pm2 reload coliseu-middleware      -- zero-downtime reload
 */
'use strict';

module.exports = {
    apps: [
        {
            name: 'coliseu-middleware',
            script: 'src/index.js',
            cwd: __dirname,

            // ── Auto-restart ─────────────────────────────────────────────────
            // PM2 reinicia automaticamente se o processo cair (exit != 0)
            autorestart: true,

            // Aguarda 3s entre tentativas de restart (evita loop imediato)
            restart_delay: 3000,

            // Máximo de restarts em 5 min — se atingir, PM2 para de reiniciar
            // e admite que há um erro crítico não recuperável.
            max_restarts: 10,
            min_uptime: '30s',   // processo precisa viver pelo menos 30s para contar como "up"

            // ── Limite de memória (evita OOM kill do SO) ─────────────────────
            // Se o processo ultrapassar 512 MB, PM2 faz restart preventivo.
            max_memory_restart: '512M',

            // ── Modo cluster (opcional — 1 worker por padrão) ────────────────
            // Deixe em 1 para simplicidade. Aumente se precisar de mais throughput:
            //   instances: 'max'  → usa todos os cores da CPU
            instances: 1,
            exec_mode: 'fork',   // 'cluster' para múltiplos workers

            // ── Variáveis de ambiente ────────────────────────────────────────
            env: {
                NODE_ENV: 'development',
            },
            env_production: {
                NODE_ENV: 'production',
            },

            // ── Watch (NÃO ativar em produção — causa restart a cada deploy parcial) ──
            watch: false,

            // ── Logs ─────────────────────────────────────────────────────────
            // Os arquivos de log são rotacionados automaticamente pelo pm2-logrotate.
            // Instale com: pm2 install pm2-logrotate
            out_file: './logs/pm2-out.log',
            error_file: './logs/pm2-error.log',
            merge_logs: true,
            log_date_format: 'YYYY-MM-DD HH:mm:ss Z',

            // ── Health check integrado ────────────────────────────────────────
            // PM2 faz GET /health a cada 30s. Se falhar 3 vezes seguidas, reinicia.
            // Requer o pacote: pm2 install pm2-health
            // (alternativa: usar o Cron ou um script externo conforme instrução abaixo)
            //
            // Alternativa sem plugin — script de healthcheck externo (cron):
            // */5 * * * * /opt/coliseu/scripts/healthcheck.sh >> /var/log/coliseu-health.log 2>&1
        },
    ],
};

/**
 * Logger JSON de uma linha — legível no Coolify/Docker e fácil de filtrar.
 * Sem dependência externa: o volume de log desta API é pequeno.
 */
'use strict';

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const min = LEVELS[process.env.LOG_LEVEL] ?? LEVELS.info;

function write(level, msg, meta) {
    if (LEVELS[level] < min) return;
    const line = { t: new Date().toISOString(), level, msg, ...meta };
    (level === 'error' || level === 'warn' ? process.stderr : process.stdout)
        .write(JSON.stringify(line) + '\n');
}

module.exports = {
    debug: (msg, meta) => write('debug', msg, meta),
    info: (msg, meta) => write('info', msg, meta),
    warn: (msg, meta) => write('warn', msg, meta),
    error: (msg, meta) => write('error', msg, meta),
};

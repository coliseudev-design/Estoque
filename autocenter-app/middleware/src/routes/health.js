'use strict';

const express = require('express');
const router = express.Router();
const db = require('../db/postgres');
const redis = require('../db/redis');

/**
 * Endpoint de Health Check
 * Usado pelo Coolify / Load Balancers para atestar que o serviço está UP.
 */
router.get('/', async (req, res) => {
    try {
        const dbOk = await db.checkConnection();
        const redisOk = redis.status === 'ready';

        if (!dbOk) {
            return res.status(503).json({ status: 'DOWN', reason: 'PostgreSQL indisponível' });
        }

        res.status(200).json({
            status: 'UP',
            service: 'AutoCenter Middleware',
            dependencies: {
                postgres: dbOk ? 'OK' : 'DOWN',
                redis: redisOk ? 'OK' : 'DOWN'
            },
            timestamp: new Date().toISOString()
        });
    } catch (err) {
        res.status(500).json({ status: 'ERROR', error: err.message });
    }
});

/**
 * Liveness Probe (Apenas diz se o processo Node está vivo e não travou C-Stack)
 */
router.get('/liveness', (req, res) => {
    res.status(200).json({ status: 'UP' });
});

/**
 * Readiness Probe (Dependências OK para receber tráfego)
 */
router.get('/readiness', async (req, res) => {
    try {
        const dbOk = await db.checkConnection();
        const redisOk = redis.status === 'ready';

        if (!dbOk || !redisOk) {
            return res.status(503).json({ 
                status: 'DOWN', 
                reason: 'Dependencies Unavailable',
                postgres: dbOk,
                redis: redisOk
            });
        }
        res.status(200).json({ status: 'READY' });
    } catch (err) {
        res.status(500).json({ status: 'ERROR', error: err.message });
    }
});

module.exports = router;

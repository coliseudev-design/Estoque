'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');

const config = require('./config/env');
const path = require('path');
const { requireDeviceJwt, requireInternalAuth } = require('./middleware/auth');
const { errorHandler }  = require('./middleware/errorHandler');
const { defaultLimit }  = require('./middleware/rateLimiter');

// Rotas
const healthRouter    = require('./routes/health');
const vehiclesRouter  = require('./routes/vehicles');
const quotesRouter    = require('./routes/quotes');
const customersRouter = require('./routes/customers');
const catalogRouter   = require('./routes/catalog');
const filiaisRouter   = require('./routes/filiais');
const serviceOrdersRouter = require('./routes/service-orders');
const techniciansRouter = require('./routes/technicians');
const sellersRouter = require('./routes/sellers');
const erpConfigRouter = require('./routes/erp-config');

const app = express();

app.use(helmet());

app.use(cors({
    origin: config.security.allowedOrigins.length > 0
        ? config.security.allowedOrigins
        : '*',
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'PUT'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Internal-Key', 'X-Branch-Id'],
}));

app.use(express.json({ limit: '5mb' }));

// Serve arquivos estáticos (Fotos de Orçamentos)
const uploadDir = process.env.UPLOAD_DIR || path.join(require('os').tmpdir(), 'coliseu_uploads');
app.use('/uploads', express.static(uploadDir));

// Health Check público
app.use('/health', healthRouter);

// Rotas Autenticadas para o Mobile App
// Todas exigem login no dispositivo via Coliseu.Identity (retornando JWT)
app.use('/api', requireDeviceJwt);
app.use('/api', defaultLimit);

app.use('/api/vehicles', vehiclesRouter);
app.use('/api/quotes',   quotesRouter);
app.use('/api/customers', customersRouter);
app.use('/api/catalog', catalogRouter);
app.use('/api/filiais', filiaisRouter);
app.use('/api/service-orders', serviceOrdersRouter);
app.use('/api/technicians', techniciansRouter);
app.use('/api/sellers', sellersRouter);
app.use('/api', erpConfigRouter);

// Rotas internas — usadas pelo Worker (X-Internal-Key)
// O Worker manda lotes de clientes do Firebird aqui
app.use('/internal', requireInternalAuth);
app.use('/internal/quotes', quotesRouter);
app.use('/internal/customers', customersRouter);
app.use('/internal/catalog', catalogRouter);
app.use('/internal/vehicles', require('./routes/vehicles.internal'));
app.use('/internal/service-orders', serviceOrdersRouter);
app.use('/internal/technicians', techniciansRouter);
app.use('/internal/sellers', sellersRouter);
app.use('/internal', erpConfigRouter);

app.use((req, res) => {
    res.status(404).json({ error: 'Rota não encontrada', code: 'NOT_FOUND' });
});

// Centralized error handler
app.use(errorHandler);

module.exports = app;

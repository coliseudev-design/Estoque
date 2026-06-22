/**
 * salesApiService.js — Consome os endpoints administrativos do Sales API.
 *
 * Autenticado via VITE_SALES_API_KEY (Admin-Api-Key) para a maioria dos endpoints.
 * Para os endpoints de pedidos/KPI/eventos, o nginx injeta a chave server-side
 * (proxy seguro: /api/sales/admin/orders/* → middleware admin-api-key injetado).
 *
 * URL base: VITE_SALES_API_URL (ex: https://licencas.coliseusistemas.com.br)
 *
 * Endpoints consumidos:
 * - GET  /api/admin/stats             → métricas globais
 * - GET  /api/admin/config            → configuração efetiva
 * - GET  /api/admin/logs              → últimas requisições
 * - GET  /api/monitoring/summary      → sync por empresa
 * - GET  /api/sales/admin/orders/report  → relatório de vendas (proxy nginx)
 * - GET  /api/sales/admin/orders/kpi    → KPIs agregados (proxy nginx)
 * - GET  /api/sales/admin/orders/events → audit trail (proxy nginx)
 * - GET  /api/admin/companies         → lista empresas
 * - POST /api/admin/companies         → cria empresa
 * - PATCH /api/admin/companies/:id    → ativa/desativa empresa
 * - POST /api/admin/companies/:id/rotate-key → rotaciona API Key
 * - GET  /api/admin/companies/:id/webhooks   → lista webhooks
 * - POST /api/admin/companies/:id/webhooks   → cria webhook
 * - PATCH /api/admin/companies/:id/webhooks/:wid → toggle webhook
 * - DELETE /api/admin/companies/:id/webhooks/:wid → remove webhook
 */
import axios from 'axios';

const salesApi = axios.create({
    baseURL: import.meta.env.VITE_SALES_API_URL || 'https://localhost:5000',
    headers: { 'Content-Type': 'application/json' },
});

// Injeta Admin-Api-Key em todas as requisições diretas ao middleware
salesApi.interceptors.request.use((config) => {
    const apiKey = import.meta.env.VITE_SALES_API_KEY || '';
    if (apiKey) config.headers['Admin-Api-Key'] = apiKey;
    return config;
});

/**
 * proxyApi — Axios para chamadas same-origin roteadas pelo nginx.
 *
 * O nginx intercepta /api/sales/admin/orders/* e injeta o Admin-Api-Key
 * server-side a partir da variável de ambiente ADMIN_API_KEY do container.
 * Não requer CORS (mesmo domínio) e nunca exige chave no bundle JS.
 */
const proxyApi = axios.create({
    // URL base vazia = requisições relativas resolvidas para a origem atual
    // (https://adminlicencas.coliseusistemas.com.br)
    headers: { 'Content-Type': 'application/json' },
    timeout: 30000,
});

export const salesApiService = {

    // ── Saúde ──────────────────────────────────────────────────────────────────

    /** Verifica se o Sales API está online. */
    checkHealth: async () => {
        try {
            const res = await axios.get(
                `${import.meta.env.VITE_SALES_API_URL || 'https://localhost:5000'}/health`,
                { timeout: 4000 }
            );
            return res.status === 200 ? res.data : null;
        } catch {
            return null;
        }
    },

    // ── Monitoramento ──────────────────────────────────────────────────────────

    /** Métricas globais: pedidos por status, catálogo, uptime, último sync. */
    getStats: async () => (await salesApi.get('/api/admin/stats')).data,

    /** Configuração efetiva atual do Sales API. */
    getConfig: async () => (await salesApi.get('/api/admin/config')).data,

    /** Últimas N requisições do buffer em memória. */
    getLogs: async (count = 50, errorsOnly = null) => {
        const params = { count };
        if (errorsOnly !== null) params.errorsOnly = errorsOnly;
        return (await salesApi.get('/api/admin/logs', { params })).data;
    },

    /** Sumário de sync por empresa. */
    getAllSummaries: async () => (await salesApi.get('/api/monitoring/summary')).data,

    // ── Pedidos ────────────────────────────────────────────────────────────────

    /**
     * Pedidos para o Relatório de Vendas.
     * Roteado via proxy nginx — Admin-Api-Key injetado server-side.
     * @param {{ from: string, to: string, page?: number, limit?: number }} params
     */
    getOrders: async ({ from, to, page = 1, limit = 50 } = {}) =>
        (await proxyApi.get('/api/sales/admin/orders/report', { params: { from, to, page, limit } })).data,

    /**
     * KPIs agregados de vendas (Dashboard KPI).
     * Roteado via proxy nginx — Admin-Api-Key injetado server-side.
     * @param {{ from: string, to: string }} params
     */
    getKpi: async ({ from, to, companyId = '', branchId = '', source = 'app' } = {}) =>
        (await proxyApi.get('/api/sales/admin/orders/kpi', { params: { from, to, companyId, branchId, source } })).data,

    /**
     * Lista filiais de uma empresa no painel admin.
     * Roteado via proxy nginx.
     */
    getBranches: async (companyId) =>
        (await proxyApi.get(`/api/sales/admin/orders/companies/${companyId}/branches`)).data,

    /**
     * Retorna lista de pedidos travados na fila pending do SQLite e Postgres
     * Roteado via proxy nginx
     * @param {{ from: string, to: string }} params
     */
    getStuckOrders: async ({ from, to } = {}) =>
        (await proxyApi.get('/api/sales/admin/orders/stuck', { params: { from, to } })).data,

    /** Força o reprocessamento manual de um pedido travado */
    retryStuckOrder: async (id) =>
        (await proxyApi.post(`/api/sales/admin/orders/stuck/${id}/retry`)).data,

    /** Força o reprocessamento manual de um cliente travado */
    retryStuckCustomer: async (localId) =>
        (await proxyApi.post(`/api/sales/admin/customers/stuck/${localId}/retry`)).data,

    /** Remove um pedido travado na fila (descarte) */
    deleteStuckOrder: async (id) =>
        (await proxyApi.delete(`/api/sales/admin/orders/stuck/${id}`)).data,

    /** Remove um cliente travado na fila (descarte) */
    deleteStuckCustomer: async (localId) =>
        (await proxyApi.delete(`/api/sales/admin/customers/stuck/${localId}`)).data,

    /**
     * Histórico de eventos dos pedidos (Audit Trail).
     * Roteado via proxy nginx — Admin-Api-Key injetado server-side.
     * @param {{ page?: number, limit?: number, orderId?: string }} params
     */
    getEvents: async ({ page = 1, limit = 50, orderId = '' } = {}) => {
        const params = { page, limit };
        if (orderId) params.orderId = orderId;
        return (await proxyApi.get('/api/sales/admin/orders/events', { params })).data;
    },

    // ── Admin: Empresas ────────────────────────────────────────────────────────

    /** Lista todas as empresas do Middleware. */
    getAdminCompanies: async () => (await salesApi.get('/api/admin/companies')).data,

    /**
     * Cria uma nova empresa no Middleware.
     * @param {string} name - Nome da empresa
     * @param {string} externalId - UUID da empresa no Identity
     */
    createAdminCompany: async (name, externalId) =>
        (await salesApi.post('/api/admin/companies', { name, externalId })).data,

    /**
     * Ativa ou desativa uma empresa.
     * @param {string} id - UUID da empresa
     * @param {boolean} active
     */
    toggleAdminCompany: async (id, active) =>
        (await salesApi.patch(`/api/admin/companies/${id}`, { active })).data,

    /**
     * Rotaciona a API Key de uma empresa.
     * @param {string} id - UUID da empresa
     */
    rotateAdminKey: async (id) =>
        (await salesApi.post(`/api/admin/companies/${id}/rotate-key`)).data,

    // ── Admin: Webhooks ────────────────────────────────────────────────────────

    /** Lista webhooks de uma empresa. */
    getWebhooks: async (companyId) =>
        (await salesApi.get(`/api/admin/companies/${companyId}/webhooks`)).data,

    /** Cria um webhook para uma empresa. */
    createWebhook: async (companyId, payload) =>
        (await salesApi.post(`/api/admin/companies/${companyId}/webhooks`, payload)).data,

    /**
     * Ativa/desativa um webhook.
     * @param {string} companyId
     * @param {string} webhookId
     * @param {boolean} active
     */
    toggleWebhook: async (companyId, webhookId, active) =>
        (await salesApi.patch(`/api/admin/companies/${companyId}/webhooks/${webhookId}`, { active })).data,

    /** Remove um webhook. */
    deleteWebhook: async (companyId, webhookId) =>
        (await salesApi.delete(`/api/admin/companies/${companyId}/webhooks/${webhookId}`)).data,
};

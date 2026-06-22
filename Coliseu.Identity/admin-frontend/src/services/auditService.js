/**
 * auditService.js — Serviço de auditoria para o painel admin.
 * Consome GET /admin/audit-logs no Coliseu Identity API.
 * Rule-01: usa o intercepor de auth (Bearer token JWT admin).
 */

import api from './api';

/**
 * Lista logs de auditoria paginados com filtros opcionais.
 * @param {number} page - Página atual (1-indexed)
 * @param {number} pageSize - Itens por página
 * @param {Object} filters - { companyId, action, from, to }
 * @returns {Promise<{ items: AuditLog[], total: number, page: number, pageSize: number }>}
 */
export const getAuditLogs = async (page = 1, pageSize = 50, filters = {}) => {
    const params = new URLSearchParams({ page, pageSize });

    if (filters.companyId)  params.append('companyId',  filters.companyId);
    if (filters.action)     params.append('action',     filters.action);
    if (filters.from)       params.append('from',       filters.from);
    if (filters.to)         params.append('to',         filters.to);
    if (filters.adminEmail) params.append('adminEmail', filters.adminEmail);

    const response = await api.get(`/admin/audit-logs?${params.toString()}`);
    return response.data;
};

/**
 * Ações conhecidas para filtro de dropdown.
 */
export const AUDIT_ACTIONS = [
    'company.created',
    'company.updated',
    'company.deleted',
    'device.activated',
    'device.revoked',
    'admin.login',
    'admin.login.2fa',
    'key.generated',
    'key.revoked',
];

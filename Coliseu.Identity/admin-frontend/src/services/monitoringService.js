/**
 * monitoringService.js — Consome o Sales API para dados de sync por empresa.
 * Endpoint: GET /api/monitoring/summary/{companyId}
 * 
 * Nota: O Sales API roda em porta diferente da Identity API.
 * A URL base é configurada via VITE_SALES_API_URL.
 */
import axios from 'axios';

const salesApi = axios.create({
    baseURL: import.meta.env.VITE_SALES_API_URL || 'https://localhost:5000',
    headers: { 'Content-Type': 'application/json' },
});

// Injetar API Key do Worker no header (a mesma chave usada pelo Worker)
salesApi.interceptors.request.use((config) => {
    const apiKey = import.meta.env.VITE_SALES_API_KEY || '';
    if (apiKey) config.headers['API-Key'] = apiKey;
    return config;
});

export const monitoringService = {
    /**
     * Busca o resumo de sync de uma empresa específica.
     * @param {string} companyId - ID da empresa (UUID)
     */
    getCompanySummary: async (companyId) => {
        const response = await salesApi.get(`/api/monitoring/summary/${companyId}`);
        return response.data;
    },

    /**
     * Busca o resumo de todas as empresas (visão admin global).
     */
    getAllSummaries: async () => {
        const response = await salesApi.get('/api/monitoring/summary');
        return response.data;
    },
};

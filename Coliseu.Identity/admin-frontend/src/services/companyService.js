import api from './api';

/**
 * Serviço centralizado de empresas.
 * Orquestra criação tanto na Identity API (5170) quanto na Sales API (tenant).
 */
export const companyService = {

    // ── Identity API ───────────────────────────────────────────────────────

    /**
     * Lista empresas da Identity API com paginação e busca.
     */
    getCompanies: async (page = 1, pageSize = 20, search = '') => {
        const response = await api.get('/admin/companies', {
            params: { page, pageSize, search }
        });
        return response.data;
    },

    getCompanyById: async (id) => {
        const response = await api.get(`/admin/companies/${id}`);
        return response.data;
    },

    /**
     * Cria empresa na Identity API e provisiona automaticamente o tenant
     * na Sales API. Retorna { company, apiKey, salesTenantCreated }.
     *
     * @param {{ name: string, deviceLimit?: number, contactEmail?: string }} payload
     */
    createCompany: async (payload) => {
        // 1) Criar na Identity API
        const identityRes = await api.post('/admin/companies', payload);
        // Response: { companyId, companyName, companyKey, deviceLimit }
        const raw = identityRes.data;
        const company = {
            id: raw.companyId,
            name: raw.companyName,
            deviceLimit: raw.deviceLimit,
        };
        const apiKey = raw.companyKey;

        // 2) Tentar criar tenant na Sales API (fire-and-forget)
        let salesTenantCreated = false;
        try {
            const salesBase = localStorage.getItem('salesApiBase') || 'http://localhost:5000';
            const salesAdminKey = localStorage.getItem('salesAdminKey') || 'dev-admin-key';

            const salesRes = await fetch(`${salesBase}/api/admin/companies`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Admin-Api-Key': salesAdminKey,
                },
                body: JSON.stringify({ name: company.name, externalId: company.id }),
            });
            salesTenantCreated = salesRes.ok;
        } catch {
            salesTenantCreated = false;
        }

        return { company, apiKey, salesTenantCreated };
    },

    updateCompanyStatus: async (id, status) => {
        const response = await api.patch(`/admin/companies/${id}/status`, { status });
        return response.data;
    },

    updateFirebirdConfig: async (id, config) => {
        const response = await api.put(`/admin/companies/${id}/firebird`, config);
        return response.data;
    },

    /**
     * Re-gera a API Key (CompanyKey) da empresa via Identity API.
     * A nova chave é retornada uma única vez — o admin deve copiá-la imediatamente.
     * Endpoint: POST /admin/companies/{id}/rotate-key
     *
     * @param {string} id - UUID da empresa
     * @returns {{ companyId, companyName, newCompanyKey }}
     */
    rotateApiKey: async (id) => {
        const response = await api.post(`/admin/companies/${id}/rotate-key`);
        return response.data;
    },

    // ── Devices ────────────────────────────────────────────────────────────

    getDevicesByCompany: async (companyId, page = 1, pageSize = 20) => {
        const response = await api.get(`/admin/devices/by-company/${companyId}`, {
            params: { page, pageSize }
        });
        return response.data;
    },

    createPendingDevice: async (companyId, activationKey) => {
        const response = await api.post('/admin/devices', { companyId, activationKey });
        return response.data;
    },

    updateDeviceStatus: async (deviceId, status) => {
        const response = await api.patch(`/admin/devices/${deviceId}/status`, { status });
        return response.data;
    },

    updateDeviceName: async (deviceId, name) => {
        const response = await api.patch(`/admin/devices/${deviceId}/name`, { name });
        return response.data;
    },

    updateCompany: async (id, payload) => {
        const response = await api.put(`/admin/companies/${id}`, payload);
        return response.data;
    },

    // ── Logo ─────────────────────────────────────────────────────────────

    /**
     * Envia logo (Base64 com prefixo data:...) para a empresa.
     */
    uploadLogo: async (id, logoBase64) => {
        const response = await api.put(`/admin/companies/${id}/logo`, { logoBase64 });
        return response.data;
    },

    /**
     * Remove a logo da empresa.
     */
    deleteLogo: async (id) => {
        const response = await api.delete(`/admin/companies/${id}/logo`);
        return response.data;
    },

    /**
     * Exclui permanentemente a empresa da Identity API.
     * SuperAdmin only — ação irreversível.
     * @param {string} id - UUID da empresa
     */
    deleteCompany: async (id) => {
        const response = await api.delete(`/admin/companies/${id}`);
        return response.data;
    },

    /**
     * Retorna a URL da logo (GET retorna bytes de imagem).
     */
    getLogoUrl: (id) => {
        const base = api.defaults.baseURL || '';
        return `${base}/admin/companies/${id}/logo`;
    },

    // ── Modules ────────────────────────────────────────────────────────────

    /**
     * Lista todos os módulos ativos de uma empresa.
     * @param {string} companyId
     * @returns {Array<{id, companyId, moduleSlug, deviceLimit, isActive, middlewareBaseUrl, createdAt}>}
     */
    listModules: async (companyId) => {
        const response = await api.get(`/admin/companies/${companyId}/modules`);
        return response.data;
    },

    /**
     * Adiciona um módulo a uma empresa.
     * A API Key é retornada uma única vez — copiar imediatamente.
     * @param {string} companyId
     * @param {{ moduleSlug: string, deviceLimit: number, middlewareBaseUrl?: string }} payload
     * @returns {{ moduleId, companyId, moduleSlug, apiKey, deviceLimit, middlewareBaseUrl }}
     */
    addModule: async (companyId, payload) => {
        const response = await api.post(`/admin/companies/${companyId}/modules`, payload);
        return response.data;
    },

    /**
     * Atualiza configurações de um módulo (deviceLimit, URL, ativo/inativo).
     */
    updateModule: async (companyId, moduleId, payload) => {
        const response = await api.put(`/admin/companies/${companyId}/modules/${moduleId}`, payload);
        return response.data;
    },

    /**
     * Rotaciona a API Key de um módulo.
     * A nova chave é retornada uma única vez.
     * @returns {{ moduleId, moduleSlug, newApiKey }}
     */
    rotateModuleKey: async (companyId, moduleId) => {
        const response = await api.post(`/admin/companies/${companyId}/modules/${moduleId}/rotate-key`);
        return response.data;
    },

    /**
     * Remove um módulo de uma empresa (SuperAdmin only).
     */
    removeModule: async (companyId, moduleId) => {
        const response = await api.delete(`/admin/companies/${companyId}/modules/${moduleId}`);
        return response.data;
    },

    // ── Branches (Multi-tenant ERP) ────────────────────────────────────────

    /**
     * Lista as filiais de uma empresa.
     * @param {string} companyId
     * @returns {Array<{id, name, cnpj, erpEmpresaId, erpDeptoPadrao, erpCentroPadrao, isDefault}>}
     */
    getBranches: async (companyId) => {
        const response = await api.get(`/admin/companies/${companyId}/branches`);
        return response.data;
    },

    /**
     * Cria uma nova filial para uma empresa.
     * @param {string} companyId
     * @param {{ name, cnpj?, erpEmpresaId, erpDeptoPadrao?, erpCentroPadrao?, isDefault? }} payload
     */
    createBranch: async (companyId, payload) => {
        const response = await api.post(`/admin/companies/${companyId}/branches`, payload);
        return response.data;
    },

    /**
     * Atualiza os dados de uma filial existente.
     * @param {string} companyId
     * @param {string} branchId
     * @param {{ name?, cnpj?, erpEmpresaId?, erpDeptoPadrao?, erpCentroPadrao?, isDefault? }} payload
     */
    updateBranch: async (companyId, branchId, payload) => {
        const response = await api.put(`/admin/companies/${companyId}/branches/${branchId}`, payload);
        return response.data;
    },

    /**
     * Exclui uma filial de uma empresa.
     * @param {string} companyId
     * @param {string} branchId
     */
    deleteBranch: async (companyId, branchId) => {
        const response = await api.delete(`/admin/companies/${companyId}/branches/${branchId}`);
        return response.data;
    },
};


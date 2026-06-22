import api from './api';

export const requestService = {
  listRequests: async () => {
    try {
      const response = await api.get('/admin/requests?page=1&pageSize=1000');
      const items = response.data?.items || [];
      return items.map(req => {
        let status = req.status;
        if (status === 'Pending') status = 'Pendente';
        else if (status === 'Approved') status = 'Aprovada';
        else if (status === 'Rejected') status = 'Recusada';
        return { 
          ...req, 
          status,
          createdAt: req.requestedAt || req.createdAt 
        };
      });
    } catch (err) {
      console.error('Error listing requests:', err);
      throw err;
    }
  },
  createRequest: async (payload) => {
    try {
      // Ajustar o payload do frontend para o formato esperado pelo backend
      // O frontend envia os módulos solicitados no formato { slug, deviceLimit }
      // O backend espera { moduleSlug, deviceLimit }
      const formattedModules = payload.modules?.map(m => ({
        moduleSlug: m.slug || m.moduleSlug,
        deviceLimit: m.deviceLimit || 1
      })) || [];

      // O frontend envia branches (array de objetos) no payload de criação.
      // O backend espera o JSON stringificado das branches no campo BranchesJson.
      const branchesJson = payload.branches ? JSON.stringify(payload.branches) : null;

      const apiPayload = {
        partnerId: payload.partnerId,
        companyName: payload.companyName,
        clientCnpj: payload.cnpj || payload.clientCnpj,
        clientCompanyType: payload.companyType || payload.clientCompanyType || 'Empresa Individual',
        costCenterCode: payload.costCenter || payload.costCenterCode,
        deptCode: payload.department || payload.deptCode,
        priceTableMode: payload.priceTableMode || 'none',
        allowNegativeStock: payload.allowNegativeStock || false,
        firebirdHost: payload.firebirdHost || 'localhost',
        firebirdDatabasePath: payload.firebirdDatabasePath,
        firebirdUser: payload.firebirdUser || 'SYSDBA',
        firebirdPassword: payload.firebirdPassword || 'masterkey',
        notes: payload.notes,
        modules: formattedModules,
        branchesJson: branchesJson
      };

      const response = await api.post('/admin/requests', apiPayload);
      return response.data;
    } catch (err) {
      console.error('Error creating request:', err);
      throw err;
    }
  },
  updateStatus: async (id, status, rejectReason = null) => {
    try {
      if (status === 'Aprovada' || status === 'Approved') {
        const response = await api.post(`/admin/requests/${id}/approve`, {
          reviewNotes: rejectReason || ''
        });
        return response.data;
      } else if (status === 'Recusada' || status === 'Rejected') {
        const response = await api.post(`/admin/requests/${id}/reject`, {
          reviewNotes: rejectReason || 'Recusada pelo administrador'
        });
        return response.data;
      } else {
        throw new Error(`Status não suportado para atualização via API: ${status}`);
      }
    } catch (err) {
      console.error('Error updating request status:', err);
      throw err;
    }
  },
  deleteRequest: async (id) => {
    try {
      const response = await api.delete(`/admin/requests/${id}`);
      return response.data;
    } catch (err) {
      console.error('Error deleting request:', err);
      throw err;
    }
  },
  syncRequestModulesWithCompanyModules: async (companyId) => {
    // Na API real, a sincronização é gerenciada no backend.
    // Deixamos o método aqui apenas para compatibilidade de chamadas legadas do frontend.
    return Promise.resolve();
  }
};

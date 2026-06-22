import api from './api';

export const partnerService = {
  listPartners: async () => {
    try {
      const response = await api.get('/admin/partners?page=1&pageSize=1000');
      return response.data?.items || [];
    } catch (err) {
      console.error('Error listing partners:', err);
      throw err;
    }
  },
  createPartner: async (partner) => {
    try {
      const response = await api.post('/admin/partners', partner);
      return response.data;
    } catch (err) {
      console.error('Error creating partner:', err);
      throw err;
    }
  },
  updatePartner: async (updatedPartner) => {
    try {
      const response = await api.put(`/admin/partners/${updatedPartner.id}`, updatedPartner);
      return response.data;
    } catch (err) {
      console.error('Error updating partner:', err);
      throw err;
    }
  },
  deletePartner: async (id) => {
    try {
      const response = await api.delete(`/admin/partners/${id}`);
      return response.data;
    } catch (err) {
      console.error('Error deleting partner:', err);
      throw err;
    }
  }
};

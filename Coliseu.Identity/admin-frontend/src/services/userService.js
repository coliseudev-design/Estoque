import api from './api';

/**
 * Serviço para CRUD de admin users e grupos de permissões.
 */
export const userService = {
    // ── Admin Users ──────────────────────────────────────────────────────
    listUsers: async () => {
        const { data } = await api.get('/admin/users');
        return data;
    },

    createUser: async (payload) => {
        const { data } = await api.post('/admin/users', payload);
        return data;
    },

    updateUser: async (id, payload) => {
        const { data } = await api.put(`/admin/users/${id}`, payload);
        return data;
    },

    deleteUser: async (id) => {
        const { data } = await api.delete(`/admin/users/${id}`);
        return data;
    },

    resetPassword: async (id, newPassword) => {
        const { data } = await api.post(`/admin/users/${id}/reset-password`, { newPassword });
        return data;
    },

    // ── Permission Groups ────────────────────────────────────────────────
    listGroups: async () => {
        const { data } = await api.get('/admin/permission-groups');
        return data;
    },

    createGroup: async (payload) => {
        const { data } = await api.post('/admin/permission-groups', payload);
        return data;
    },

    updateGroup: async (id, payload) => {
        const { data } = await api.put(`/admin/permission-groups/${id}`, payload);
        return data;
    },

    deleteGroup: async (id) => {
        const { data } = await api.delete(`/admin/permission-groups/${id}`);
        return data;
    },

    getAvailablePermissions: async () => {
        const { data } = await api.get('/admin/permission-groups/available-permissions');
        return data;
    },
};

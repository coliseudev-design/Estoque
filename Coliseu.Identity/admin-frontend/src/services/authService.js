import api from './api';

/**
 * Decodifica um JWT (sem validar assinatura) e retorna o payload.
 * @param {string} token
 * @returns {object|null}
 */
function decodeJwt(token) {
    try {
        const base64Url = token.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        return JSON.parse(atob(base64));
    } catch {
        return null;
    }
}

/**
 * Extrai as claims 'perm' do JWT e retorna como array de strings.
 * @param {string} token
 * @returns {string[]}
 */
function extractPermissions(token) {
    const payload = decodeJwt(token);
    if (!payload) return [];
    const perm = payload['perm'];
    if (!perm) return [];
    return Array.isArray(perm) ? perm : [perm];
}

export const authService = {
    login: async (email, password) => {
        const response = await api.post('/admin/auth/login', { email, password });
        const data = response.data;

        if (data?.accessToken && !data?.requiresTwoFactor) {
            localStorage.setItem('adminToken', data.accessToken);
            localStorage.setItem('adminUser', JSON.stringify({
                email:       data.email || email,
                name:        data.name  || data.email || email,
                role:        data.role  || 'Operator',
                permissions: extractPermissions(data.accessToken),
            }));
        }

        return data;
    },

    verify2fa: async (email, totpCode) => {
        const response = await api.post('/admin/auth/2fa/verify', { email, totpCode });
        const data = response.data;

        if (data?.accessToken) {
            localStorage.setItem('adminToken', data.accessToken);
            localStorage.setItem('adminUser', JSON.stringify({
                email:       data.email || email,
                name:        data.name  || data.email || email,
                role:        data.role  || 'Operator',
                permissions: extractPermissions(data.accessToken),
            }));
        }

        return data;
    },

    /**
     * Setup de 2FA: gera secret e retorna URI otpauth:// para QR Code.
     */
    setup2fa: async (email, totpCode = '') => {
        const response = await api.post('/admin/auth/2fa/setup', { email, totpCode });
        return response.data;
    },

    /**
     * Desativa o 2FA do admin autenticado.
     */
    disable2fa: async () => {
        const response = await api.post('/admin/auth/2fa/disable');
        return response.data;
    },

    logout: () => {
        localStorage.removeItem('adminToken');
        window.location.href = '/';
    },

    isAuthenticated: () => {
        return !!localStorage.getItem('adminToken');
    }
};

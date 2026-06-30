// Toast Notification Manager
function showToast(message, type = 'success') {
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.className = 'toast-container';
        document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `toast toast-${type} glass-panel`;
    
    const icon = document.createElement('span');
    icon.innerHTML = type === 'success' ? '✓' : '✗';
    icon.style.fontWeight = 'bold';
    icon.style.fontSize = '1.1rem';
    
    const text = document.createElement('span');
    text.innerText = message;

    toast.appendChild(icon);
    toast.appendChild(text);
    container.appendChild(toast);

    // Auto-remove after 4 seconds
    setTimeout(() => {
        toast.style.animation = 'slideIn 0.3s reverse';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// AJAX API Requests Helper
async function apiRequest(url, method = 'GET', body = null) {
    const headers = {
        'Content-Type': 'application/json',
    };
    
    // Check if token exists in localStorage (JWT auth support)
    const token = localStorage.getItem('access_token');
    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }

    const options = { method, headers };
    if (body) {
        options.body = JSON.stringify(body);
    }

    try {
        const response = await fetch(url, options);
        if (response.status === 401) {
            // Unauthorized, redirect to login
            window.location.href = '/adm/login';
            return null;
        }
        
        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.detail || 'Ocorreu um erro no processamento.');
        }
        return data;
    } catch (error) {
        showToast(error.message, 'error');
        throw error;
    }
}

// Action Trigger Functions
async function testIntegration(companyId, integrationId) {
    try {
        showToast('Testando conexão...', 'success');
        const res = await apiRequest(`/adm/api/companies/${companyId}/integrations/${integrationId}/test`, 'PATCH');
        if (res && res.success) {
            showToast('Integração funcionando perfeitamente!', 'success');
            // Reload window after delay to show updated 'last_tested_at'
            setTimeout(() => window.location.reload(), 1500);
        } else {
            showToast('Falha na integração: ' + (res.message || 'Erro desconhecido'), 'error');
        }
    } catch (err) {
        // Error already toast-displayed in apiRequest
    }
}

async function rotateApiKey(companyId) {
    if (!confirm('Deseja realmente rotacionar as chaves de acesso? As chaves antigas expirarão imediatamente.')) {
        return;
    }
    try {
        const res = await apiRequest(`/adm/api/companies/${companyId}/api-keys`, 'POST', { name: 'Chave Rotacionada' });
        if (res) {
            showToast('Chave de acesso gerada com sucesso!', 'success');
            setTimeout(() => window.location.reload(), 1500);
        }
    } catch (err) {}
}

async function revokeApiKey(companyId, keyId) {
    if (!confirm('Deseja realmente revogar esta chave de acesso?')) {
        return;
    }
    try {
        await apiRequest(`/adm/api/companies/${companyId}/api-keys/${keyId}`, 'DELETE');
        showToast('Chave revogada com sucesso!', 'success');
        setTimeout(() => window.location.reload(), 1000);
    } catch (err) {}
}

async function forceInstanceSync(companyId, instanceId) {
    try {
        showToast('Forçando sincronização...', 'success');
        const res = await apiRequest(`/adm/api/companies/${companyId}/instances/${instanceId}/sync`, 'POST');
        if (res && res.success) {
            showToast('Sincronização forçada enviada com sucesso!', 'success');
            setTimeout(() => window.location.reload(), 1500);
        }
    } catch (err) {}
}

async function toggleCompanyStatus(companyId, newStatus) {
    try {
        const res = await apiRequest(`/adm/api/companies/${companyId}/status`, 'PATCH', { status: newStatus });
        if (res) {
            showToast(`Status da empresa atualizado para: ${newStatus}`, 'success');
            setTimeout(() => window.location.reload(), 1000);
        }
    } catch (err) {}
}

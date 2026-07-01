// Toast Notifications Helper
function showToast(message, type = 'success') {
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.className = 'toast-container';
        document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerText = message;
    
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Global Cart State
let cart = [];

function getCartTotal() {
    return cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
}

function updateCartDOM() {
    const container = document.getElementById('cart-items-container');
    if (!container) return; // not on order screen

    container.innerHTML = '';
    
    if (cart.length === 0) {
        container.innerHTML = `<div style="text-align: center; padding: 30px; color: var(--text-muted); font-size: 0.9rem;">Carrinho Vazio</div>`;
        document.getElementById('total-items-qty').innerText = '0';
        document.getElementById('total-amount-display').innerText = 'R$ 0,00';
        return;
    }

    let totalQty = 0;
    cart.forEach(item => {
        totalQty += item.quantity;
        const row = document.createElement('div');
        row.className = 'cart-item-row';
        row.innerHTML = `
            <div style="flex: 1;">
                <div style="font-weight: 700; font-size: 0.88rem;">${item.name}</div>
                <div style="font-size: 0.78rem; color: var(--text-secondary);">R$ ${item.price.toFixed(2)} un</div>
            </div>
            <div class="cart-item-qty">
                <button type="button" class="qty-btn" onclick="adjustQty('${item.id}', -1)">-</button>
                <span style="font-weight: 700; font-size: 0.9rem; min-width: 20px; text-align: center;">${item.quantity}</span>
                <button type="button" class="qty-btn" onclick="adjustQty('${item.id}', 1)">+</button>
            </div>
            <div style="font-weight: 800; font-size: 0.9rem; color: var(--primary-color);">
                R$ ${(item.price * item.quantity).toFixed(2)}
            </div>
        `;
        container.appendChild(row);
    });

    const totalAmount = getCartTotal();
    document.getElementById('total-items-qty').innerText = totalQty;
    document.getElementById('total-amount-display').innerText = `R$ ${totalAmount.toFixed(2)}`;
}

function addToCart(id, name, price, stock) {
    const existing = cart.find(item => item.id === id);
    if (existing) {
        if (existing.quantity >= stock) {
            showToast('Quantidade máxima em estoque atingida!', 'error');
            return;
        }
        existing.quantity += 1;
    } else {
        if (stock <= 0) {
            showToast('Produto esgotado!', 'error');
            return;
        }
        cart.push({ id, name, price: parseFloat(price), quantity: 1, maxStock: stock });
    }
    showToast('Produto adicionado ao carrinho!');
    updateCartDOM();
}

function adjustQty(id, delta) {
    const item = cart.find(i => i.id === id);
    if (!item) return;

    item.quantity += delta;
    if (item.quantity > item.maxStock) {
        showToast('Quantidade máxima em estoque atingida!', 'error');
        item.quantity = item.maxStock;
    }
    if (item.quantity <= 0) {
        cart = cart.filter(i => i.id !== id);
        showToast('Produto removido.');
    }
    updateCartDOM();
}

// Debounce helper for catalog search
let debounceTimeout;
function debounceSearch() {
    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(() => {
        const query = document.getElementById('search-input').value.trim();
        searchProducts(query);
    }, 300);
}

async function searchProducts(query) {
    const grid = document.getElementById('catalog-grid-container');
    if (!grid) return;

    grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted);">Buscando...</div>';
    
    try {
        const response = await fetch(`/web-api/catalog/query?q=${encodeURIComponent(query)}`);
        const data = await response.json();
        
        grid.innerHTML = '';
        if (data.length === 0) {
            grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 40px;">Nenhum produto encontrado.</div>';
            return;
        }

        data.forEach(prod => {
            const card = document.createElement('div');
            card.className = 'product-card';
            card.innerHTML = `
                <div class="product-img">📦</div>
                <div class="product-info">
                    <div class="product-code">${prod.code}</div>
                    <div class="product-name">${prod.name}</div>
                    <div class="product-stock ${prod.stock > 0 ? 'stock-badge-green' : 'stock-badge-red'}">
                        Estoque: ${prod.stock}
                    </div>
                    <div class="product-price">R$ ${prod.price.toFixed(2)}</div>
                </div>
                <button type="button" class="btn btn-primary btn-sm" onclick="addToCart('${prod.id}', '${prod.name.replace(/'/g, "\\'")}', ${prod.price}, ${prod.stock})">
                    Adicionar
                </button>
            `;
            grid.appendChild(card);
        });
    } catch (err) {
        grid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--danger);">Falha ao carregar catálogo.</div>';
    }
}

// Checkout and submit order
async function submitOrder(status = 'order') {
    const customerSelect = document.getElementById('customer-select');
    if (!customerSelect || customerSelect.value === "") {
        showToast('Selecione um cliente para prosseguir!', 'error');
        return;
    }

    if (cart.length === 0) {
        showToast('Adicione pelo menos um item ao carrinho!', 'error');
        return;
    }

    const payload = {
        customer_id: customerSelect.value,
        status: status, // 'order' or 'budget'
        payment_condition: document.getElementById('payment-condition').value,
        items: cart.map(i => ({
            product_id: i.id,
            quantity: i.quantity,
            price: i.price
        }))
    };

    try {
        const response = await fetch('/web-api/orders/new', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        
        const resData = await response.json();
        if (response.ok) {
            showToast(status === 'budget' ? 'Orçamento salvo!' : 'Pedido realizado com sucesso!', 'success');
            cart = [];
            updateCartDOM();
            setTimeout(() => {
                window.location.href = '/orders';
            }, 1000);
        } else {
            showToast(resData.detail || 'Falha ao processar pedido.', 'error');
        }
    } catch (err) {
        showToast('Erro de conexão ao enviar pedido.', 'error');
    }
}

// Sync execution
async function forceSync() {
    showToast('Forçando sincronização com o ERP...', 'success');
    try {
        const res = await fetch('/web-api/sync/run', { method: 'POST' });
        const data = await res.json();
        if (res.ok && data.success) {
            showToast('Sincronização concluída com sucesso!', 'success');
            setTimeout(() => window.location.reload(), 1200);
        } else {
            showToast('Erro ao sincronizar: ' + (data.message || 'Erro do ERP'), 'error');
        }
    } catch (e) {
        showToast('Falha na conexão com o Middleware.', 'error');
    }
}

// Sharing Triggers
function shareWhatsApp(orderId) {
    showToast('Redirecionando para o WhatsApp...', 'success');
    window.open(`/orders/${orderId}/share/whatsapp`, '_blank');
}

function shareEmail(orderId) {
    showToast('Enviando e-mail para o cliente...', 'success');
    fetch(`/orders/${orderId}/share/email`, { method: 'POST' })
        .then(res => res.json())
        .then(data => {
            if (data.success) showToast('E-mail enviado com sucesso!', 'success');
            else showToast('Falha ao enviar e-mail: ' + data.message, 'error');
        })
        .catch(() => showToast('Erro de rede ao enviar e-mail.', 'error'));
}

// Modal Toggle Helpers
function openModal(id) {
    document.getElementById(id).classList.add('open');
}

function closeModal(id) {
    document.getElementById(id).classList.remove('open');
}

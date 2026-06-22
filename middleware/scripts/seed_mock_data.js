/**
 * Seed script — Popula o middleware com dados mock realistas via POST.
 * Uso: node scripts/seed_mock_data.js
 *
 * Requer: middleware rodando com FB_MOCK=true na porta configurada.
 */
'use strict';

const API_KEY = process.env.API_KEY || 'CONFIGURE_AQUI_UMA_KEY_FORTE';
const BASE = process.env.BASE_URL || 'http://localhost:3000';

async function post(path, body) {
    const res = await fetch(`${BASE}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'API-Key': API_KEY },
        body: JSON.stringify(body),
    });
    const data = await res.json();
    console.log(`✅ POST ${path} → ${JSON.stringify(data)}`);
}

async function seed() {
    // ── Vendedores ────────────────────────────────────────────────────────
    await post('/api/sync/sellers', {
        sellers: [
            { id: 1, mobileId: '1', name: 'Roberto Silva', email: 'roberto@coliseu.com', passwordHash: '1234', maxDiscount: 15, commissionRate: 5 },
            { id: 2, mobileId: '2', name: 'Carlos Mendes', email: 'carlos@coliseu.com', passwordHash: '5678', maxDiscount: 10, commissionRate: 4 },
            { id: 3, mobileId: '3', name: 'Ana Oliveira', email: 'ana@coliseu.com', passwordHash: '0000', maxDiscount: 20, commissionRate: 6 },
        ]
    });

    // ── Clientes ──────────────────────────────────────────────────────────
    await post('/api/sync/customers', {
        customers: [
            { id: 101, name: 'Construtora Alpha LTDA', tradeName: 'Alpha Construções', cnpj: '12.345.678/0001-01', address: 'Av. Brasil, 1500', city: 'São Paulo', state: 'SP', phone: '(11) 3456-7890', mobile: '(11) 99876-5432', email: 'contato@alpha.com', sellerId: 1, creditLimit: 50000, status: 'A' },
            { id: 102, name: 'Ferragista Beto & Cia', tradeName: 'Beto Ferragens', cnpj: '23.456.789/0001-02', address: 'Rua São João, 320', city: 'Campinas', state: 'SP', phone: '(19) 2345-6789', mobile: '(19) 98765-4321', email: 'vendas@betoferr.com', sellerId: 1, creditLimit: 30000, status: 'A' },
            { id: 103, name: 'Material de Construção Show', tradeName: 'MC Show', cnpj: '34.567.890/0001-03', address: 'Av. Independência, 88', city: 'Ribeirão Preto', state: 'SP', phone: '(16) 3345-6789', mobile: '(16) 97654-3210', email: 'compras@mcshow.com', sellerId: 2, creditLimit: 80000, status: 'A' },
            { id: 104, name: 'Depósito Central do Sul', tradeName: 'Central Sul', cnpj: '45.678.901/0001-04', address: 'Rod. Raposo, km 42', city: 'Sorocaba', state: 'SP', phone: '(15) 4456-7890', mobile: '(15) 96543-2109', email: 'pedidos@centralsul.com', sellerId: 2, creditLimit: 120000, status: 'A' },
            { id: 105, name: 'Marcenaria Premium EIRELI', tradeName: 'Premium Madeiras', cnpj: '56.789.012/0001-05', address: 'Rua XV de Novembro, 1020', city: 'Curitiba', state: 'PR', phone: '(41) 5567-8901', mobile: '(41) 95432-1098', email: 'orcamento@premium.com', sellerId: 3, creditLimit: 45000, status: 'A' },
            { id: 106, name: 'Empreendimentos Horizonte SA', tradeName: 'Horizonte', cnpj: '67.890.123/0001-06', address: 'Av. Paulista, 2000', city: 'São Paulo', state: 'SP', phone: '(11) 6678-9012', mobile: '(11) 94321-0987', email: 'cfo@horizonte.com', sellerId: 1, creditLimit: 250000, status: 'A' },
        ]
    });

    // ── Catálogo de Produtos ──────────────────────────────────────────────
    await post('/api/sync/catalog', {
        products: [
            { code: 'P001', name: 'Cimento CP-II 50kg', nameShort: 'Cimento 50kg', stock: 850, unit: 'SC', brand: 'Votoran', reference: 'CP2-50', barCode: '7891234560010', maxDiscount: 10, price: 38.90, priceMin: 35.00, priceCost: 28.50 },
            { code: 'P002', name: 'Argamassa AC-II Interna 20kg', nameShort: 'Argamassa AC2', stock: 420, unit: 'SC', brand: 'Quartzolit', reference: 'AC2-20I', barCode: '7891234560027', maxDiscount: 12, price: 24.50, priceMin: 22.00, priceCost: 17.80 },
            { code: 'P003', name: 'Tijolo Cerâmico 9x19x29', nameShort: 'Tijolo 9x19', stock: 15000, unit: 'UN', brand: 'Cerâmica SP', reference: 'TC-0929', barCode: '7891234560034', maxDiscount: 8, price: 1.20, priceMin: 1.05, priceCost: 0.72 },
            { code: 'P004', name: 'Vergalhão CA-50 10mm 12m', nameShort: 'Vergalhão 10mm', stock: 580, unit: 'BR', brand: 'Gerdau', reference: 'CA50-10', barCode: '7891234560041', maxDiscount: 5, price: 42.00, priceMin: 40.00, priceCost: 34.20 },
            { code: 'P005', name: 'Areia Média Lavada m³', nameShort: 'Areia Média', stock: 200, unit: 'M3', brand: 'Mineradora X', reference: 'AM-LAV', barCode: '7891234560058', maxDiscount: 15, price: 120.00, priceMin: 105.00, priceCost: 78.00 },
            { code: 'P006', name: 'Brita 1 Granítica m³', nameShort: 'Brita 1', stock: 180, unit: 'M3', brand: 'Pedreira Sul', reference: 'BR1-GR', barCode: '7891234560065', maxDiscount: 15, price: 135.00, priceMin: 118.00, priceCost: 85.00 },
            { code: 'P007', name: 'Tubo PVC 100mm 6m Esgoto', nameShort: 'Tubo PVC 100', stock: 340, unit: 'UN', brand: 'Tigre', reference: 'PVC100-6', barCode: '7891234560072', maxDiscount: 10, price: 45.90, priceMin: 41.00, priceCost: 33.50 },
            { code: 'P008', name: 'Fio Elétrico 2.5mm² 100m Azul', nameShort: 'Fio 2.5mm Azul', stock: 250, unit: 'RL', brand: 'Prysmian', reference: 'FIO25-AZ', barCode: '7891234560089', maxDiscount: 8, price: 189.00, priceMin: 175.00, priceCost: 142.00 },
            { code: 'P009', name: 'Chapa Drywall ST 1.20x1.80', nameShort: 'Drywall ST', stock: 620, unit: 'UN', brand: 'Placo', reference: 'DW-ST18', barCode: '7891234560096', maxDiscount: 12, price: 32.50, priceMin: 29.00, priceCost: 22.80 },
            { code: 'P010', name: 'Tinta Acrílica Premium 18L Branca', nameShort: 'Tinta 18L Bco', stock: 180, unit: 'GL', brand: 'Suvinil', reference: 'ACR-18BR', barCode: '7891234560102', maxDiscount: 10, price: 289.00, priceMin: 260.00, priceCost: 195.00 },
            { code: 'P011', name: 'Porta MDP 80x210 Mogno', nameShort: 'Porta Mogno', stock: 45, unit: 'UN', brand: 'Eucatex', reference: 'PT-80MG', barCode: '7891234560119', maxDiscount: 7, price: 189.00, priceMin: 175.00, priceCost: 128.00 },
            { code: 'P012', name: 'Fechadura Interna Cromada', nameShort: 'Fechadura Int', stock: 120, unit: 'UN', brand: 'Pado', reference: 'FI-CROM', barCode: '7891234560126', maxDiscount: 10, price: 49.90, priceMin: 45.00, priceCost: 32.00 },
            { code: 'P013', name: 'Piso Cerâmico 60x60 Cinza m²', nameShort: 'Piso 60x60', stock: 2800, unit: 'M2', brand: 'Eliane', reference: 'PC-60CZ', barCode: '7891234560133', maxDiscount: 12, price: 39.90, priceMin: 35.00, priceCost: 25.50 },
            { code: 'P014', name: 'Rejunte Flexível 1kg Cinza', nameShort: 'Rejunte 1kg', stock: 950, unit: 'UN', brand: 'Quartzolit', reference: 'RJ-1CZ', barCode: '7891234560140', maxDiscount: 15, price: 12.90, priceMin: 11.00, priceCost: 8.20 },
            { code: 'P015', name: 'Impermeabilizante 18L', nameShort: 'Impermeab 18L', stock: 90, unit: 'GL', brand: 'Vedacit', reference: 'IMP-18', barCode: '7891234560157', maxDiscount: 8, price: 320.00, priceMin: 295.00, priceCost: 215.00 },
        ]
    });

    // ── Formas de Pagamento ───────────────────────────────────────────────
    await post('/api/sync/payment-species', {
        species: [
            { id: 1, name: 'Dinheiro', type: 'AV', days: 0 },
            { id: 2, name: 'PIX', type: 'AV', days: 0 },
            { id: 3, name: 'Boleto 30 dias', type: 'PR', days: 30 },
            { id: 4, name: 'Boleto 30/60', type: 'PR', days: 60 },
            { id: 5, name: 'Cartão Crédito', type: 'CR', days: 30 },
            { id: 6, name: 'Cheque 30 dias', type: 'CH', days: 30 },
        ]
    });

    // ── Naturezas de Operação ─────────────────────────────────────────────
    await post('/api/sync/natureza', {
        naturezas: [
            { id: 1, description: 'Venda', type: 'S', mobileAccess: 'S' },
            { id: 2, description: 'Venda Futura', type: 'S', mobileAccess: 'S' },
            { id: 3, description: 'Bonificação', type: 'S', mobileAccess: 'S' },
            { id: 4, description: 'Orçamento', type: 'S', mobileAccess: 'S' },
        ]
    });

    // ── Títulos Financeiros (em aberto) ──────────────────────────────────
    await post('/api/sync/financials', {
        financials: [
            { id: 1001, customerId: 101, docNumber: 'NF-4521', amount: 12500.00, interest: 0, dueDate: '2026-03-15', paymentSpeciesId: 3, paidDate: null, type: 'R', isPaid: 0 },
            { id: 1002, customerId: 101, docNumber: 'NF-4380', amount: 8200.00, interest: 0, dueDate: '2026-02-28', paymentSpeciesId: 4, paidDate: null, type: 'R', isPaid: 0 },
            { id: 1003, customerId: 103, docNumber: 'NF-4610', amount: 32000.00, interest: 150, dueDate: '2026-02-20', paymentSpeciesId: 3, paidDate: null, type: 'R', isPaid: 0 },
            { id: 1004, customerId: 104, docNumber: 'NF-4102', amount: 5600.00, interest: 0, dueDate: '2026-04-10', paymentSpeciesId: 5, paidDate: null, type: 'R', isPaid: 0 },
        ]
    });

    console.log('\n🎉 Seed concluído! Middleware populado com dados de demonstração.');
}

seed().catch(err => {
    console.error('❌ Seed falhou:', err.message);
    process.exit(1);
});

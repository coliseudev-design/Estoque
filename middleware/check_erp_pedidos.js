'use strict';
const Firebird = require('node-firebird');

const options = {
    host: '127.0.0.1',
    port: 3050,
    database: 'C:\\Coliseu\\Data\\PIVETA.FDB',
    user: 'SYSDBA',
    password: 'masterkey',
    lowercase_keys: false,
};

Firebird.attach(options, (err, db) => {
    if(err) return console.error(err);
    
    // Consulta para ver os últimos 10 pedidos gerados diretamente no ERP (não iniciam com MOB)
    const query = `
        SELECT FIRST 10 
            ID_PEDIDO, 
            PEDIDO, 
            DATA_HORA, 
            DATA_VENCIMENTO,
            STATUS,
            TIPO,
            ITENS,
            QTDE_TOTAL,
            VALOR_PEDIDO
        FROM PEDIDOS 
        WHERE PEDIDO NOT LIKE 'MOB%'
        ORDER BY ID_PEDIDO DESC
    `;
    
    db.query(query, (err, rows) => {
        if(err) { console.error('Erro na query:', err); db.detach(); return; }
        
        console.log('=== PEDIDOS DIRETOS DO ERP ===');
        console.table(rows);
        
        // Vamos ver se existe alguma diferença em PEDIDOS_DOCS ou PEDIDO_ITENS para um pedido do ERP vs um pedido MOB
        // Vamos pegar o último pedido ERP e o último pedido MOB
        db.query(`SELECT FIRST 1 ID_PEDIDO FROM PEDIDOS WHERE PEDIDO LIKE 'MOB%' ORDER BY ID_PEDIDO DESC`, (e1, r1) => {
            db.query(`SELECT FIRST 1 ID_PEDIDO FROM PEDIDOS WHERE PEDIDO NOT LIKE 'MOB%' ORDER BY ID_PEDIDO DESC`, (e2, r2) => {
                const mobId = r1?.[0]?.ID_PEDIDO;
                const erpId = r2?.[0]?.ID_PEDIDO;
                
                if (mobId && erpId) {
                    console.log(`Comparando itens de Pedido MOB (${mobId}) com Pedido ERP (${erpId})`);
                    db.query(`SELECT ID_PRODUTO, QTDE, VALOR_UNITARIO, VALOR_FINAL_UN, DESCONTO, VALOR_TOTAL FROM PEDIDO_ITENS WHERE ID_PEDIDO = ?`, [mobId], (e3, r3) => {
                        console.log(`Itens do Pedido MOB (${mobId}):`);
                        console.table(r3);
                        
                        db.query(`SELECT ID_PRODUTO, QTDE, VALOR_UNITARIO, VALOR_FINAL_UN, DESCONTO, VALOR_TOTAL FROM PEDIDO_ITENS WHERE ID_PEDIDO = ?`, [erpId], (e4, r4) => {
                            console.log(`Itens do Pedido ERP (${erpId}):`);
                            console.table(r4);
                            db.detach();
                        });
                    });
                } else {
                    db.detach();
                }
            });
        });
    });
});

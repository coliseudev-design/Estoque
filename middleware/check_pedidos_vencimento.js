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
    
    // Consulta para ver as colunas de data/vencimento e status dos últimos 10 pedidos Mobile
    const query = `
        SELECT FIRST 10 
            ID_PEDIDO, 
            PEDIDO, 
            DATA_HORA, 
            STATUS,
            TIPO
        FROM PEDIDOS 
        WHERE PEDIDO LIKE 'MOB%'
        ORDER BY ID_PEDIDO DESC
    `;
    
    db.query(query, (err, rows) => {
        if(err) { console.error('Erro na query:', err); db.detach(); return; }
        
        console.log('=== PEDIDOS MOBILE ===');
        console.table(rows);
        
        // Vamos verificar se a coluna DATA_VENCIMENTO existe na tabela PEDIDOS
        const checkColumnSql = `
            SELECT RDB$FIELD_NAME 
            FROM RDB$RELATION_FIELDS 
            WHERE TRIM(RDB$RELATION_NAME) = 'PEDIDOS' AND TRIM(RDB$FIELD_NAME) = 'DATA_VENCIMENTO'
        `;
        
        db.query(checkColumnSql, (err2, cols) => {
            if (err2) { console.error(err2); db.detach(); return; }
            if (cols && cols.length > 0) {
                console.log('A coluna DATA_VENCIMENTO existe na tabela PEDIDOS!');
                
                // Se existe, vamos rodar uma query trazendo DATA_VENCIMENTO dos últimos pedidos MOB
                db.query(`
                    SELECT FIRST 10 ID_PEDIDO, PEDIDO, DATA_HORA, DATA_VENCIMENTO, STATUS 
                    FROM PEDIDOS 
                    WHERE PEDIDO LIKE 'MOB%'
                    ORDER BY ID_PEDIDO DESC
                `, (err3, results) => {
                    if (err3) console.error(err3);
                    else console.table(results);
                    db.detach();
                });
            } else {
                console.log('A coluna DATA_VENCIMENTO NÃO existe na tabela PEDIDOS!');
                db.detach();
            }
        });
    });
});

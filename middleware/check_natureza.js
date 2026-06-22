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
    
    const mobId = 529699;
    const erpId = 529674;
    
    const query = `
        SELECT 
            p.ID_PEDIDO, 
            p.PEDIDO, 
            p.ID_NATUREZA, 
            p.STATUS, 
            p.TIPO,
            n.OPERACAO,
            n.TIPO AS NAT_TIPO,
            n.PROCESSO AS NAT_PROCESSO,
            n.CALC_COMISSAO
        FROM PEDIDOS p
        LEFT JOIN NATUREZA_OPERACAO n ON n.ID_NATUREZA = p.ID_NATUREZA
        WHERE p.ID_PEDIDO IN (?, ?)
    `;
    
    db.query(query, [mobId, erpId], (e, r) => {
        if(e) console.error(e);
        console.table(r);
        db.detach();
    });
});

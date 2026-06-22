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
    
    db.query(`SELECT * FROM PEDIDOS_DOCS WHERE ID_PEDIDO = ?`, [mobId], (e1, r1) => {
        console.log(`Documentos (PEDIDOS_DOCS) do Pedido MOB (${mobId}):`);
        console.table(r1);
        
        db.query(`SELECT * FROM PEDIDOS_DOCS WHERE ID_PEDIDO = ?`, [erpId], (e2, r2) => {
            console.log(`Documentos (PEDIDOS_DOCS) do Pedido ERP (${erpId}):`);
            console.table(r2);
            db.detach();
        });
    });
});

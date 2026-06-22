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
    
    db.query(`SELECT * FROM PEDIDOS WHERE ID_PEDIDO = ?`, [mobId], (e1, r1) => {
        db.query(`SELECT * FROM PEDIDOS WHERE ID_PEDIDO = ?`, [erpId], (e2, r2) => {
            const mobRow = r1?.[0];
            const erpRow = r2?.[0];
            
            if (mobRow && erpRow) {
                console.log('=== COMPARISON OF PEDIDOS ROWS ===');
                const allKeys = Array.from(new Set([...Object.keys(mobRow), ...Object.keys(erpRow)])).sort();
                
                const diffs = [];
                for (const key of allKeys) {
                    const mobVal = mobRow[key];
                    const erpVal = erpRow[key];
                    if (String(mobVal) !== String(erpVal)) {
                        diffs.push({
                            Field: key,
                            MobileValue: mobVal,
                            ERPValue: erpVal
                        });
                    }
                }
                console.table(diffs);
            } else {
                console.log('Rows not found.');
            }
            db.detach();
        });
    });
});

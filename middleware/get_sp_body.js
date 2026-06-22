'use strict';
const Firebird = require('node-firebird');

const options = {
    host: '127.0.0.1',
    port: 3050,
    database: 'C:\\Coliseu\\Data\\PIVETA.FDB',
    user: 'SYSDBA',
    password: 'masterkey',
    lowercase_keys: false,
    role: null,
    pageSize: 4096,
};

Firebird.attach(options, function(err, db) {
    if (err) {
        console.error('Error connecting to Firebird:', err);
        return;
    }

    const query = `
        SELECT RDB$PROCEDURE_SOURCE 
        FROM RDB$PROCEDURES 
        WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO'
    `;
    
    db.query(query, function(err, result) {
        if (err) {
            console.error('Error querying:', err);
            db.detach();
            return;
        }
        
        if (result && result.length > 0) {
            console.log('=== BODY OF MOB_CADASTRAR_PEDIDO ===');
            console.log(result[0].RDB$PROCEDURE_SOURCE);
        } else {
            console.log('Procedure not found.');
        }
        db.detach();
    });
});

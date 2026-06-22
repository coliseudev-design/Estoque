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
        SELECT FIRST 5 ID_PEDIDO, DATA, CLIENTE, TOTAL_PEDIDO, EMPRESA, DEPTO, CENTRO_CUSTO
        FROM PEDIDOS 
        ORDER BY ID_PEDIDO DESC
    `;
    
    db.query(query, function(err, result) {
        if (err) {
            console.error('Error querying:', err);
            db.detach();
            return;
        }
        
        console.table(result);
        db.detach();
    });
});

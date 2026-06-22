const Firebird = require('node-firebird');
const fs = require('fs');
const options = { host: '127.0.0.1', port: 3050, database: 'C:\\Coliseu\\Data\\PIVETA.FDB', user: 'SYSDBA', password: 'masterkey', lowercase_keys: false };
Firebird.attach(options, (err, db) => {
    if(err) return console.error(err);
    db.query("SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO'", (err, res) => {
        if(err) { console.error(err); db.detach(); return; }
        res[0].RDB$PROCEDURE_SOURCE(function(err, name, e) {
            let buffer = Buffer.alloc(0);
            e.on('data', chunk => buffer = Buffer.concat([buffer, chunk]));
            e.on('end', () => { fs.writeFileSync('sp_source.txt', buffer.toString('latin1')); db.detach(); });
        });
    });
});

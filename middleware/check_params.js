const Firebird = require('node-firebird');
const options = { host: '127.0.0.1', port: 3050, database: 'C:\\Coliseu\\Data\\PIVETA.FDB', user: 'SYSDBA', password: 'masterkey', lowercase_keys: false };
Firebird.attach(options, (err, db) => {
    if(err) return console.error(err);
    db.query("SELECT RDB$PARAMETER_NAME, RDB$PARAMETER_NUMBER FROM RDB$PROCEDURE_PARAMETERS WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO' AND RDB$PARAMETER_TYPE = 0 ORDER BY RDB$PARAMETER_NUMBER", (err, res) => {
        if(err) console.error(err); else console.table(res);
        db.detach();
    });
});

const Firebird = require('node-firebird');

const options = {
    host: 'localhost',
    port: 3050,
    database: 'C:\\Coliseu\\Data\\PIVETA.FDB',
    user: 'SYSDBA',
    password: 'masterkey',
    lowercase_keys: false,
    role: null,
    pageSize: 4096,
};

Firebird.attach(options, function (err, db) {
    if (err) {
        console.error('Erro ao conectar', err);
        process.exit(1);
    }
    db.query(`SELECT COUNT(*) AS QTD FROM PRODUTOS`, function (err, result) {
        if (err) console.error(err);
        else console.log('Total PRODUTOS:', result);

        db.query(`SELECT COUNT(*) AS QTD FROM PRODUTO_PRECOS WHERE ATIVO = 1`, function (err2, result2) {
            if (err2) console.error(err2);
            else console.log('Total PRECOS ATIVOS:', result2);
            db.detach();
            process.exit(0);
        });
    });
});

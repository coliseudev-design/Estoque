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
    if (err) { console.error('Erro ao conectar', err); process.exit(1); }

    const query = `
        SELECT COUNT(*) AS QTD
        FROM PRODUTOS P
        INNER JOIN PRODUTO_PRECOS PP ON PP.ID_PRODUTO = P.ID_PRODUTO AND PP.ATIVO = 1
        LEFT JOIN CATEGORIAS C ON C.ID_CATEGORIA = P.ID_CATEGORIA
        WHERE COALESCE(P.BLOQUEADO, 0) = 0
    `;

    const queryLimpa = `
        SELECT COUNT(*) AS QTD
        FROM PRODUTOS P
        INNER JOIN PRODUTO_PRECOS PP ON PP.ID_PRODUTO = P.ID_PRODUTO AND PP.ATIVO = 1
    `;

    db.query(query, function (err, result) {
        if (err) console.error("Erro QUERY ORIGINAL:", err.message);
        else console.log('Total QUERY ORIGINAL:', result);

        db.query(queryLimpa, function (err2, result2) {
            if (err2) console.error("Erro QUERY LIMPA:", err2.message);
            else console.log('Total QUERY LIMPA:', result2);

            db.detach();
            process.exit(0);
        });
    });
});

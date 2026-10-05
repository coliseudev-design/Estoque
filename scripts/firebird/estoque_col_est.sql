/* ============================================================================
   Coliseu Estoque — tabelas de retorno da conferência no Firebird do ERP
   (fonte oficial — o Worker leva uma cópia em workerVet/docs/sql/estoque_col_est.sql)

   QUEM RODA: o DBA / implantador, uma única vez, no IBExpert, FlameRobin ou isql.
   O Worker NUNCA cria tabela: ele só grava nestas duas, e só com
   EstoqueApi:WriteBack:Enabled = true.

   Compatível com Firebird 2.5 e 3.0 (identificadores ≤ 31 caracteres).
   ============================================================================ */

CREATE TABLE COL_EST_CONFERENCIA (
    ID_COLISEU      CHAR(36)       NOT NULL,   -- id do documento no Coliseu Estoque
    ORIGEM          VARCHAR(5)     NOT NULL,   -- NFS (nota de saída) | PED (pedido)
    CHAVE_ERP       VARCHAR(30)    NOT NULL,   -- TBNOTASSAIDA.CHAVE
    NUMERO          VARCHAR(30),
    STATUS          VARCHAR(25)    NOT NULL,   -- CONCLUIDO | CONCLUIDO_DIVERGENTE
    DIVERGENTE      SMALLINT       DEFAULT 0 NOT NULL,
    RODADAS         SMALLINT       DEFAULT 1 NOT NULL,
    OPERADOR        VARCHAR(120),
    OPERADOR_LOGIN  VARCHAR(60),
    APROVADOR       VARCHAR(120),
    JUSTIFICATIVA   VARCHAR(1000),
    INICIO          TIMESTAMP,
    FIM             TIMESTAMP,
    APROVADO_EM     TIMESTAMP,
    GRAVADO_EM      TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT PK_COL_EST_CONFERENCIA PRIMARY KEY (ID_COLISEU)
);

CREATE INDEX IX_COL_EST_CONF_CHAVE ON COL_EST_CONFERENCIA (ORIGEM, CHAVE_ERP);

CREATE TABLE COL_EST_CONFERENCIA_ITEM (
    ID_COLISEU      CHAR(36)       NOT NULL,
    SEQ             INTEGER        NOT NULL,   -- TBMOVESTOQUE.SEQUENCIAITEM; ≥ 100000 = produto fora do documento
    CODPRODUTO      VARCHAR(30)    NOT NULL,
    QTD_ESPERADA    NUMERIC(18,4)  NOT NULL,
    QTD_CONFERIDA   NUMERIC(18,4)  NOT NULL,
    RESULTADO       VARCHAR(10)    NOT NULL,   -- OK | FALTA | SOBRA
    EXTRA           SMALLINT       DEFAULT 0 NOT NULL,
    CONSTRAINT PK_COL_EST_CONF_ITEM PRIMARY KEY (ID_COLISEU, SEQ),
    CONSTRAINT FK_COL_EST_CONF_ITEM FOREIGN KEY (ID_COLISEU)
        REFERENCES COL_EST_CONFERENCIA (ID_COLISEU) ON DELETE CASCADE
);

COMMIT;

/* ── Opcional e recomendado: usuário dedicado à gravação ──────────────────────
   Com ele, o próprio Firebird garante que o Worker só consegue escrever nas
   tabelas COL_EST_*. Configure em EstoqueApi:WriteBack:User / Password.

CREATE USER COLISEU_ESTOQUE PASSWORD 'troque-esta-senha';
GRANT SELECT ON RDB$RELATIONS TO COLISEU_ESTOQUE;
GRANT SELECT, INSERT, UPDATE, DELETE ON COL_EST_CONFERENCIA      TO COLISEU_ESTOQUE;
GRANT SELECT, INSERT, UPDATE, DELETE ON COL_EST_CONFERENCIA_ITEM TO COLISEU_ESTOQUE;
COMMIT;
*/

/* ── Exemplo de consulta para o ERP/relatórios ───────────────────────────────
SELECT n.NUMNOTA, c.STATUS, c.OPERADOR, c.FIM, i.CODPRODUTO, i.QTD_ESPERADA, i.QTD_CONFERIDA, i.RESULTADO
  FROM COL_EST_CONFERENCIA c
  JOIN TBNOTASSAIDA n ON CAST(n.CHAVE AS VARCHAR(30)) = c.CHAVE_ERP
  JOIN COL_EST_CONFERENCIA_ITEM i ON i.ID_COLISEU = c.ID_COLISEU
 WHERE c.FIM >= CURRENT_DATE - 7;
*/

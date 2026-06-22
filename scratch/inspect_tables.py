import fdb

def inspect():
    con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
    cur = con.cursor()
    
    print("\n=== TEST VIEW QUERY ===")
    sql = """
        SELECT
            d.ID_DEPTO                                               AS depto_id,
            COALESCE(TRIM(d.DESCRICAO), '')                          AS nome,
            COALESCE(TRIM(e.CNPJ), '')                               AS documento,
            COALESCE(TRIM(d.OP_ESTOQUE), '')                         AS centro_custo,
            COALESCE(c.ID_EMPRESA, 1)                                AS empresa_erp,
            CASE WHEN c.ID_EMPRESA = 1 THEN 1 ELSE 0 END             AS is_default
        FROM DEPARTAMENTOS d
        LEFT JOIN CONFIG c ON c.DEPTO_PADRAO = d.ID_DEPTO
        LEFT JOIN EMPRESA e ON e.ID_EMPRESA = c.ID_EMPRESA
    """
    try:
        cur.execute(sql)
        for r in cur.fetchall():
            print(f"depto_id: {r[0]}, nome: {r[1]}, documento/cnpj: {r[2]}, centro_custo: {r[3]}, empresa_erp: {r[4]}, is_default: {r[5]}")
    except Exception as e:
        print(f"Error executing test query: {e}")

    con.close()

if __name__ == "__main__":
    inspect()

import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

print('TIPO | DC       | QTD    | Exemplo DESCRICAO')
print('-'*75)

for tipo in [1, 3, 4, 6]:
    cur.execute('SELECT FIRST 1 TIPO, DC, DESCRICAO FROM CONTAS WHERE TIPO = ?', [tipo])
    r = cur.fetchone()
    
    cur2 = conn.cursor()
    cur2.execute('SELECT COUNT(*) FROM CONTAS WHERE TIPO = ?', [tipo])
    cnt = cur2.fetchone()[0]
    
    dc_label = 'RECEBER' if r[1] == 1 else 'PAGAR'
    descricao = (r[2] or '')[:45]
    print(f'  {tipo}  | {dc_label:7} | {cnt:6} | {descricao}')

# Verifica se TIPO 1 e TIPO 4 podem ser ambos RECEBER e PAGAR
print()
print('=== Distribuicao DC por TIPO ===')
cur.execute("""
    SELECT TIPO, DC, COUNT(*) as QTD
    FROM CONTAS
    GROUP BY TIPO, DC
    ORDER BY TIPO, DC
""")
for row in cur.fetchall():
    dc = 'RECEBER' if row[1] == 1 else 'PAGAR'
    print(f'  TIPO {row[0]} | {dc:7} | {row[2]:6} registros')

conn.close()

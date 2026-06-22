import fdb
import re

try:
    con = fdb.connect(dsn='localhost:C:/Coliseu/Data/BRANDAO.FDB', user='SYSDBA', password='masterkey')
    cur = con.cursor()
    with open('C:/Users/rober/.gemini/antigravity/scratch/Coliseu_Sales/ColiseuSales.Configurator/FirebirdBootstrapper.cs', 'r', encoding='utf-8') as f:
        text = f.read()
        match = re.search(r'const string spMobCadastrarPedidoItem = @\"(.*?)\";', text, re.DOTALL)
        if match:
            sp = match.group(1)
            try:
                cur.execute(sp)
                con.commit()
                print('Success')
            except Exception as e:
                print('Error:')
                print(e)
        else:
            print('Not found')
except Exception as e:
    print('Conn error:', e)

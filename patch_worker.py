import re

with open('worker/Jobs/SyncDashboardDataJob.cs', 'r', encoding='utf-8') as f:
    content = f.read()

# Add await SyncCaixasAsync
if 'await SyncCaixasAsync(ct);' not in content:
    content = content.replace("await SyncFinanceiroAsync(ct);", "await SyncCaixasAsync(ct);\n            await SyncFinanceiroAsync(ct);")

# Add con.ID_CAIXA
if 'con.ID_CAIXA' not in content:
    content = content.replace("con.ID_CLIENTE                                           AS cliente_id_firebird,", "con.ID_CLIENTE                                           AS cliente_id_firebird,\n                con.ID_CAIXA                                             AS caixa_id_firebird,")

# Add SyncCaixasAsync method
caixas_method = """
    private async Task SyncCaixasAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT
                ID_CAIXA AS id_firebird,
                DESCRICAO AS descricao
            FROM CAIXAS
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Dash_Caixas", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        int count = data.Count;
        if (count == 0)
        {
            _store.Update("Dash_Caixas", 0, DateTime.Now, "Nenhum registro encontrado");
            return;
        }

        _store.Update("Dash_Caixas", count, null, "Enviando para nuvem...");
        await PushToMiddlewareAsync("dash_caixas", "Dash_Caixas", data, ct);
    }
"""

if 'private async Task SyncCaixasAsync' not in content:
    content = content.replace("private async Task SyncFinanceiroAsync", caixas_method + "\n    private async Task SyncFinanceiroAsync")

with open('worker/Jobs/SyncDashboardDataJob.cs', 'w', encoding='utf-8') as f:
    f.write(content)

print("Patch Worker applied")

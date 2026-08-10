using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ColiseuSales.Worker.Services;

/// <summary>
/// MonitoringServer — Mini servidor HTTP local (porta 9001) usando HttpListener.
///
/// Endpoints:
///   GET  /status      → JSON com estado de todas as entidades sincronizadas
///   GET  /logs        → Server-Sent Events (stream de log em tempo real)
///   POST /force-sync  → Sinaliza para o WorkerService executar sync imediato
///
/// Escuta apenas em localhost — zero exposição externa.
/// </summary>
public sealed class MonitoringServer
{
    private readonly StatusStore                  _store;
    private readonly ILogger<MonitoringServer>    _logger;
    private readonly HttpListener                 _listener = new();
    private readonly ManualResetEventSlim         _forceSyncSignal = new(false);

    private static readonly JsonSerializerOptions _json = new()
    {
        WriteIndented       = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public const string BaseUrl = "http://localhost:9001/";

    /// <summary>True quando o Configurador clicou em "Forçar Sync".</summary>
    public bool ConsumeForceSyncSignal()
    {
        if (!_forceSyncSignal.IsSet) return false;
        _forceSyncSignal.Reset();
        return true;
    }

    public MonitoringServer(StatusStore store, ILogger<MonitoringServer> logger)
    {
        _store  = store;
        _logger = logger;
    }

    /// <summary>Inicia o servidor em background.</summary>
    public Task StartAsync(CancellationToken ct)
    {
        try
        {
            _listener.Prefixes.Add(BaseUrl);
            _listener.Start();
            _logger.LogInformation("[Monitor] Servidor de monitoramento em {Url}", BaseUrl);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] Monitor HTTP iniciado em {BaseUrl}");
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[Monitor] Falha ao iniciar: {Error}", ex.Message);
            return Task.CompletedTask;
        }

        // Loop de requisições em background
        _ = Task.Run(() => AcceptLoopAsync(ct), ct);
        return Task.CompletedTask;
    }

    public void Stop()
    {
        try { _listener.Stop(); } catch { /* ignore */ }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _listener.IsListening)
        {
            try
            {
                var ctx = await _listener.GetContextAsync().WaitAsync(ct);
                _ = HandleAsync(ctx, ct); // fire-and-forget por request
            }
            catch (OperationCanceledException) { break; }
            catch (HttpListenerException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                _logger.LogDebug("[Monitor] AcceptLoop: {Error}", ex.Message);
            }
        }
    }

    private async Task HandleAsync(HttpListenerContext ctx, CancellationToken ct)
    {
        var req  = ctx.Request;
        var resp = ctx.Response;

        // CORS para o Configurador local
        resp.Headers.Add("Access-Control-Allow-Origin", "*");

        try
        {
            switch (req.Url?.AbsolutePath)
            {
                case "/":
                case "/dashboard":
                    await HandleDashboardAsync(resp, ct);
                    break;

                case "/status":
                    await HandleStatusAsync(resp, ct);
                    break;

                case "/logs":
                    await HandleLogsAsync(resp, ct);
                    break;

                case "/force-sync" when req.HttpMethod == "POST":
                    _forceSyncSignal.Set();
                    resp.StatusCode = 202;
                    await WriteJsonAsync(resp, new { queued = true });
                    break;

                default:
                    resp.StatusCode = 404;
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug("[Monitor] Handler: {Error}", ex.Message);
        }
        finally
        {
            try { resp.Close(); } catch { /* ignore */ }
        }
    }

    private static Task HandleDashboardAsync(HttpListenerResponse resp, CancellationToken ct)
    {
        const string html = """
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Coliseu Sales — Monitor</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0c101b;color:#e0e6f0;font-family:'Segoe UI',sans-serif;font-size:13px;padding:12px}
  h2{color:#00bb77;font-size:14px;letter-spacing:1px;text-transform:uppercase;margin-bottom:10px}
  #status-bar{display:flex;align-items:center;gap:8px;padding:8px 12px;background:#131927;border-radius:8px;margin-bottom:12px;font-size:12px}
  .dot{width:9px;height:9px;border-radius:50%;background:#555;flex-shrink:0}
  .dot.on{background:#00cc77;box-shadow:0 0 6px #00cc77}
  #cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px;margin-bottom:14px}
  .card{background:#131927;border-radius:10px;padding:12px;border:1px solid #1e2d45}
  .card-icon{font-size:20px;margin-bottom:4px}
  .card-name{color:#8899bb;font-size:11px;letter-spacing:.5px}
  .card-count{font-size:28px;font-weight:700;color:#ffffff;line-height:1.1}
  .card-date{font-size:10px;margin-top:4px}
  .card-date.ok{color:#00cc77}.card-date.err{color:#ff5555}.card-date.idle{color:#556}
  #log-box{background:#090d16;border-radius:8px;padding:10px;height:200px;overflow-y:auto;font-family:Consolas,monospace;font-size:11px;line-height:1.6;border:1px solid #1e2d45}
  .log-line{color:#00dc78}.log-err{color:#ff5555}.log-info{color:#8899bb}
  #btn-sync{margin-top:10px;background:#0078c8;color:#fff;border:none;padding:8px 18px;border-radius:6px;cursor:pointer;font-size:12px;font-family:inherit}
  #btn-sync:hover{background:#0066aa}#btn-sync:active{background:#004d88}
  #btn-clear{margin-top:10px;margin-left:8px;background:#1e2d45;color:#aaa;border:none;padding:8px 14px;border-radius:6px;cursor:pointer;font-size:12px;font-family:inherit}
  #updated{font-size:10px;color:#556;margin-left:auto}
</style>
</head>
<body>
<div id="status-bar">
  <div class="dot" id="dot"></div>
  <span id="status-txt">Conectando...</span>
  <span id="updated"></span>
</div>
<h2>ENTIDADES SINCRONIZADAS</h2>
<div id="cards"></div>
<h2>LOG EM TEMPO REAL</h2>
<div id="log-box"></div>
<div>
  <button id="btn-sync" onclick="forceSync()">⚡ Forçar Sync Agora</button>
  <button id="btn-clear" onclick="clearLog()">✕ Limpar Log</button>
</div>
<script>
const ICONS={'Sellers':'👤','Clientes':'👥','Catalog':'📦','PaymentSpecies':'💳',
  'PaymentConditions':'📅','Financeiro':'💰','PriceTables':'🏷️',
  'SalesRankings':'🏆','NaturezaOp':'📌','Desempenho':'📊'};

function icon(e){return ICONS[e]||'🔄';}

async function loadStatus(){
  try{
    const r=await fetch('/status');if(!r.ok)throw new Error('fail');
    const d=await r.json();
    document.getElementById('dot').className='dot on';
    document.getElementById('status-txt').textContent='Worker ativo — localhost:9001';
    document.getElementById('updated').textContent='Atualizado às '+new Date().toLocaleTimeString('pt-BR');
    const box=document.getElementById('cards');
    box.innerHTML=d.entities.map(e=>`
      <div class="card">
        <div class="card-icon">${icon(e.entity)}</div>
        <div class="card-name">${e.entity}</div>
        <div class="card-count">${e.count!==null?e.count.toLocaleString('pt-BR'):'—'}</div>
        <div class="card-date ${e.success===false?'err':e.lastSync?'ok':'idle'}">
          ${e.error?'✗ '+e.error:e.lastSync?'✓ '+e.lastSync:'—'}
        </div>
      </div>`).join('');
  }catch{
    document.getElementById('dot').className='dot';
    document.getElementById('status-txt').textContent='Worker offline';
  }
}

function appendLog(line){
  const box=document.getElementById('log-box');
  const cls=line.includes('ERRO')||line.includes('✗')?'log-err':line.includes('✓')?'log-line':'log-info';
  const el=document.createElement('div');
  el.className=cls;el.textContent=line;
  box.appendChild(el);
  box.scrollTop=box.scrollHeight;
  if(box.children.length>300)box.removeChild(box.firstChild);
}

function clearLog(){document.getElementById('log-box').innerHTML='';}

async function forceSync(){
  try{await fetch('/force-sync',{method:'POST'});appendLog('['+new Date().toLocaleTimeString('pt-BR')+'] ⚡ Sync forçado solicitado.');}
  catch{appendLog('['+new Date().toLocaleTimeString('pt-BR')+'] ✗ Erro ao forçar sync.');}
}

function connectSSE(){
  const es=new EventSource('/logs');
  es.onmessage=e=>{appendLog(e.data);};
  es.onerror=()=>{setTimeout(connectSSE,3000);};
}

loadStatus();
setInterval(loadStatus,5000);
connectSSE();
</script>
</body>
</html>
""";
        var bytes = Encoding.UTF8.GetBytes(html);
        resp.ContentType     = "text/html; charset=utf-8";
        resp.ContentLength64 = bytes.Length;
        return resp.OutputStream.WriteAsync(bytes, 0, bytes.Length, ct);
    }

    private async Task HandleStatusAsync(HttpListenerResponse resp, CancellationToken ct)
    {
        var payload = new
        {
            serverTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            entities   = _store.GetAll().Values.Select(r => new
            {
                entity   = r.Entity,
                count    = r.Count,
                lastSync = r.LastSync == DateTime.MinValue ? null : r.LastSync.ToString("HH:mm:ss"),
                success  = r.Success,
                error    = r.Error,
            }).ToArray(),
        };

        await WriteJsonAsync(resp, payload);
    }

    private async Task HandleLogsAsync(HttpListenerResponse resp, CancellationToken ct)
    {
        resp.ContentType  = "text/event-stream; charset=utf-8";
        resp.SendChunked  = true;
        resp.Headers.Add("Cache-Control", "no-cache");
        resp.Headers.Add("Connection", "keep-alive");

        var stream = resp.OutputStream;

        // Mensagem de handshake
        await WriteSseAsync(stream, "[Monitor conectado — aguardando eventos de sync]");

        try
        {
            await foreach (var line in _store.LogReader.ReadAllAsync(ct))
            {
                await WriteSseAsync(stream, line);
            }
        }
        catch (OperationCanceledException) { }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task WriteJsonAsync(HttpListenerResponse resp, object payload)
    {
        var json  = JsonSerializer.Serialize(payload, _json);
        var bytes = Encoding.UTF8.GetBytes(json);
        resp.ContentType     = "application/json; charset=utf-8";
        resp.ContentLength64 = bytes.Length;
        await resp.OutputStream.WriteAsync(bytes);
    }

    private static async Task WriteSseAsync(Stream stream, string data)
    {
        // SSE format: "data: <message>\n\n"
        var payload = Encoding.UTF8.GetBytes($"data: {data}\n\n");
        await stream.WriteAsync(payload);
        await stream.FlushAsync();
    }
}

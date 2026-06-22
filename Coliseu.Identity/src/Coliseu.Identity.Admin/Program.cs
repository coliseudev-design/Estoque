using Blazored.LocalStorage;
using Coliseu.Identity.Admin.Auth;
using Coliseu.Identity.Admin.Components;
using Coliseu.Identity.Admin.Services;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

// ── Blazor Services ────────────────────────────────────────────────────────
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// ── Auth & LocalStorage ────────────────────────────────────────────────────
builder.Services.AddBlazoredLocalStorage();
builder.Services.AddAuthentication();
builder.Services.AddAuthorizationCore();
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddScoped<AuthenticationStateProvider, JwtAuthenticationStateProvider>();

// ── API Services ───────────────────────────────────────────────────────────
var identityApiUrl = builder.Configuration["IdentityApi:BaseUrl"]
    ?? "http://localhost:5100";

builder.Services.AddHttpClient<IdentityApiService>(client =>
{
    client.BaseAddress = new Uri(identityApiUrl);
});

// ── Reverse Proxy (nginx faz SSL termination) ───────────────────────────────
// Necessário para que o ASP.NET reconheça o proto HTTPS vindo do Traefik/nginx.
// Sem isso, UseHttpsRedirection() entra em loop infinito (HTTP → HTTPS → HTTP → ...).
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    // Trusts qualquer rede interna Docker (nginx → admin:8081 é rede interna)
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// ───────────────────────────────────────────────────────────────────────────
var app = builder.Build();

// UseForwardedHeaders DEVE vir antes de qualquer middleware de roteamento.
// Isso faz o ASP.NET reconhecer X-Forwarded-Proto: https enviado pelo nginx.
app.UseForwardedHeaders();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // HSTS é gerenciado pelo Traefik/Coolify — não duplicar aqui.
    // app.UseHsts();
}

// UseHttpsRedirection NÃO é usado dentro de Docker + nginx.
// O nginx já recebe HTTPS via Traefik e repassa HTTP interno para o app.
// Habilitar isso causaria: nginx→HTTPS→redirect→HTTP→redirect→loop→500.

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();

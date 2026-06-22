using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net.Http;
using System.ServiceProcess;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Linq;

namespace ColiseuSales.Configurator
{
    // ─── Paleta de cores Coliseu ─────────────────────────────────────────────
    internal static class ColiseuColors
    {
        public static readonly Color Blue       = Color.FromArgb(0,   120, 200);
        public static readonly Color BlueDark   = Color.FromArgb(0,    85, 155);
        public static readonly Color BlueLight  = Color.FromArgb(230, 244, 255);
        public static readonly Color TextDark   = Color.FromArgb(30,   40,  55);
        public static readonly Color TextMid    = Color.FromArgb(90,   95, 110);
        public static readonly Color TextLight  = Color.FromArgb(155, 160, 175);
        public static readonly Color BgPage     = Color.FromArgb(247, 249, 252);
        public static readonly Color BgCard     = Color.FromArgb(255, 255, 255);
        public static readonly Color Border     = Color.FromArgb(222, 228, 237);
        public static readonly Color Success    = Color.FromArgb( 16, 185, 129);
        public static readonly Color SuccessBg  = Color.FromArgb(236, 253, 245);
        public static readonly Color Error      = Color.FromArgb(220,  38,  38);
        public static readonly Color ErrorBg    = Color.FromArgb(254, 242, 242);
        public static readonly Color Terminal   = Color.FromArgb( 12,  16,  27);
        public static readonly Color TermText   = Color.FromArgb(  0, 220, 120);
        
        // Cores específicas para a aba Monitor (Estilo Escuro "ui-ux-pro-max")
        public static readonly Color MonitorBg    = Color.FromArgb( 15,  17,  23); // Fundo escuro total
        public static readonly Color MonitorCard  = Color.FromArgb( 22,  27,  38); // Fundo dos cards
        public static readonly Color MonitorLine  = Color.FromArgb( 30,  37,  53); // Bordas e linhas
        public static readonly Color MonitorText  = Color.FromArgb(241, 245, 249); // Texto claro

        // Cores dos Módulos para o Monitor
        public static readonly Color CoreModule      = Color.FromArgb(243, 156,  18); // Laranja (#F39C12)
        public static readonly Color DashModule      = Color.FromArgb( 16, 185, 129); // Verde (#10B981)
        public static readonly Color NexusModule     = Color.FromArgb(  0, 150, 136); // Teal (#009688)
        public static readonly Color VisionModule    = Color.FromArgb(236,  72, 153); // Rosa Choque (#EC4899)
        public static readonly Color GarantiasModule = Color.FromArgb( 52, 152, 219); // Azul (#3498DB)
    }

    public partial class MainForm : Form
    {
        // ── Configurações ──────────────────────────────────────────────────────
        private TextBox txtFirebirdDb  = null!;
        private TextBox txtServiceSuffix = null!;
        private TextBox txtVpsUrl      = null!;
        private TextBox txtVpsApiKey   = null!;
        private TextBox txtIdentityUrl = null!;
        private TextBox txtTenantId    = null!;
        private TextBox    txtFirebirdUser = null!;
        private TextBox    txtFirebirdPass = null!;
        private CheckBox   chkWireCrypt    = null!;
        private CheckBox   chkSalesEnabled = null!;
        
        // ── Propriedades de Bloqueio e Segurança ─────────────────────────────────
        private Button btnUnlock = null!;
        private Button btnSave = null!;
        private Button btnBootstrap = null!;
        private Button? btnBrowse = null;
        private CheckBox chkAutoStart = null!;
        private bool _isLocked = true;

        // ── Tempos de Sincronismo ──────────────────────────────────────────────
        private NumericUpDown numCatalogSync = null!;
        private NumericUpDown numOrderSync   = null!;
        private NumericUpDown numMaxPoolSize = null!;
        private NumericUpDown numConnectionTimeout = null!;

        // ── Atendente do Futuro ──────────────────────────────────────────────
        private CheckBox chkAtendenteEnabled = null!;
        private TextBox  txtAtendenteUrl     = null!;
        private TextBox  txtAtendenteApiKey  = null!;

        // 🔧 AutoCenter
        private CheckBox chkAcEnabled = null!;
        private TextBox  txtAcUrl     = null!;
        private TextBox  txtAcApiKey  = null!;

        // 📈 Coliseu Dash
        private CheckBox chkDashEnabled = null!;
        private TextBox  txtDashUrl     = null!;
        private TextBox  txtDashApiKey  = null!;

        // 🌐 Nexus
        private CheckBox chkNexusEnabled = null!;
        private TextBox  txtNexusUrl     = null!;
        private TextBox  txtNexusApiKey  = null!;

        // 👁️ Vision
        private CheckBox chkVisionEnabled = null!;
        private TextBox  txtVisionUrl     = null!;
        private TextBox  txtVisionApiKey  = null!;

        // 🛡️ Controle de Garantias
        private CheckBox chkGarantiasEnabled = null!;
        private TextBox  txtGarantiasUrl     = null!;
        private TextBox  txtGarantiasApiKey  = null!;

        // 🖥 Monitoramento 🖥───────────────────────────────────────────
        private FlowLayoutPanel _cardsPanel = null!;
        private RichTextBox _monitorLogBox = null!;

        // ── Aba Logs nativa ───────────────────────────────────────────────────
        private RichTextBox _logBox   = null!;
        private bool        _logPause = false;  // pausa o auto-scroll para inspecionar

        // ── Estado ────────────────────────────────────────────────────────────
        private readonly SettingsManager   _settings  = new();
        private readonly HttpClient        _http      = new() { Timeout = TimeSpan.FromSeconds(5) };
        private CancellationTokenSource    _sseCts    = new();
        private System.Windows.Forms.Timer _pollTimer = null!;
        private Image?  _iconImage;
        private Image?  _fullLogoImage;

        // ── Tray ──────────────────────────────────────────────────────────────
        private NotifyIcon  _trayIcon  = null!;
        private ContextMenuStrip _trayMenu = null!;
        private bool _isQuitting = false;
        private bool _startMinimized;

        private const string MonitorBase   = "http://localhost:9001";
        private string CurrentWorkerServiceName
        {
            get
            {
                var suffix = txtServiceSuffix?.Text.Trim();
                if (string.IsNullOrEmpty(suffix))
                    return "ColiseuSales Worker";
                return $"ColiseuSalesWorker_{suffix}";
            }
        }
        private const string AutoStartKey  = "ColiseuWorkerConfigurator";
        private const string RegistryRun   = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

        // ── URLs e chaves padrão de produção ──────────────────────────────────
        private static class Defaults
        {
            public const string FirebirdDb  = "";
            public const string VpsUrl      = "https://licencas.coliseusistemas.com.br";
            public const string VpsApiKey   = "";
            public const string IdentityUrl = "https://adminlicencas.coliseusistemas.com.br";
        }

        // ─────────────────────────────────────────────────────────────────────

        public MainForm(bool startMinimized = false)
        {
            _startMinimized = startMinimized;
            LoadLogo();
            InitializeComponent();
            BuildTrayIcon();
            LoadSettings();
        }

        private void LoadLogo()
        {
            try
            {
                var asm = System.Reflection.Assembly.GetExecutingAssembly();

                // Carrega ícone embutido no .exe
                using var iconStream = asm.GetManifestResourceStream("coliseu_icon.png");
                if (iconStream != null)
                    _iconImage = Image.FromStream(iconStream);

                // Carrega logo completa embutida no .exe
                using var logoStream = asm.GetManifestResourceStream("coliseu_logo.png");
                if (logoStream != null)
                    _fullLogoImage = Image.FromStream(logoStream);
            }
            catch { /* se não encontrar, continua sem imagem */ }
        }

        // ─────────────────────────────────────────────────────────────────────
        // System Tray — NotifyIcon + menu contextual
        // ─────────────────────────────────────────────────────────────────────

        private void BuildTrayIcon()
        {
            _trayMenu = new ContextMenuStrip();

            var mnuOpen = new ToolStripMenuItem("🖥  Abrir Configurador");
            mnuOpen.Click += (_, _) => ShowMainWindow();

            var mnuStartWorker = new ToolStripMenuItem("▶  Iniciar Worker");
            mnuStartWorker.Click += (_, _) =>
            {
                try
                {
                    using var sc = new ServiceController(CurrentWorkerServiceName);
                    if (sc.Status != ServiceControllerStatus.Running)
                    {
                        sc.Start();
                        ShowBalloon("Worker iniciado", "O serviço Coliseu Sales Worker está em execução.", ToolTipIcon.Info);
                    }
                }
                catch (Exception ex) { ShowBalloon("Erro", ex.Message, ToolTipIcon.Error); }
            };

            var mnuStopWorker = new ToolStripMenuItem("⏹  Parar Worker");
            mnuStopWorker.Click += (_, _) =>
            {
                try
                {
                    using var sc = new ServiceController(CurrentWorkerServiceName);
                    if (sc.Status == ServiceControllerStatus.Running)
                    {
                        sc.Stop();
                        ShowBalloon("Worker parado", "O serviço Coliseu Sales Worker foi parado.", ToolTipIcon.Warning);
                    }
                }
                catch (Exception ex) { ShowBalloon("Erro", ex.Message, ToolTipIcon.Error); }
            };

            var mnuAutoStart = new ToolStripMenuItem("🚀  Iniciar com o Windows")
            {
                Checked = IsAutoStartEnabled(),
                CheckOnClick = true,
            };
            mnuAutoStart.CheckedChanged += (_, _) => SetAutoStart(mnuAutoStart.Checked);

            var mnuSep  = new ToolStripSeparator();
            var mnuQuit = new ToolStripMenuItem("✕  Sair");
            mnuQuit.Click += (_, _) =>
            {
                _isQuitting = true;
                Application.Exit();
            };

            _trayMenu.Items.AddRange(new ToolStripItem[]
            {
                mnuOpen, new ToolStripSeparator(),
                mnuStartWorker, mnuStopWorker, new ToolStripSeparator(),
                mnuAutoStart, mnuSep, mnuQuit,
            });

            _trayIcon = new NotifyIcon
            {
                Text    = "Coliseu Sales — Worker Monitor",
                Visible = true,
                ContextMenuStrip = _trayMenu,
            };

            // Atribui ícone ao tray (usa a imagem embutida ou ícone padrão)
            if (_iconImage is Bitmap bmpTray)
            {
                try
                {
                    var resized = new Bitmap(bmpTray, 32, 32);
                    _trayIcon.Icon = Icon.FromHandle(resized.GetHicon());
                }
                catch { _trayIcon.Icon = SystemIcons.Application; }
            }
            else
            {
                _trayIcon.Icon = SystemIcons.Application;
            }

            // Duplo-clique no ícone do tray abre a janela
            _trayIcon.DoubleClick += (_, _) => ShowMainWindow();
        }

        private void ShowMainWindow()
        {
            Show();
            WindowState   = FormWindowState.Normal;
            ShowInTaskbar = true;
            Activate();
        }

        // ─────────────────────────────────────────────────────────────────────
        // Auto-Start via Agendador de Tarefas (Task Scheduler)
        // Motivo: méodo mais aceito por antivírus — task visível no Agendador,
        // usa nível de privilégio limitado (RL LIMITED), sem modificar Registro.
        // ─────────────────────────────────────────────────────────────────────

        private const string TaskName = "Coliseu Sales Worker Monitor";

        private bool IsAutoStartEnabled()
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo("schtasks.exe",
                    $"/Query /TN \"{TaskName}\"")
                {
                    WindowStyle     = System.Diagnostics.ProcessWindowStyle.Hidden,
                    CreateNoWindow  = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                };
                using var p = System.Diagnostics.Process.Start(psi)!;
                p.WaitForExit(3000);
                return p.ExitCode == 0; // 0 = tarefa existe
            }
            catch { return false; }
        }

        private bool SetAutoStart(bool enable)
        {
            try
            {
                string args;
                if (enable)
                {
                    // Cria tarefa que inicia ao login com delay de 30s
                    // /RL LIMITED  = privilégio normal (sem admin)
                    // /F           = sobrescreve se já existir
                    // /DELAY       = aguarda 30s após login para não atrasar o boot
                    var exePath = Application.ExecutablePath;
                    args = $"/Create /F /TN \"{TaskName}\" " +
                           $"/TR \"\\\"{exePath}\\\" --minimized\" " +
                           $"/SC ONLOGON /DELAY 0000:30 /RL LIMITED";
                }
                else
                {
                    args = $"/Delete /F /TN \"{TaskName}\"";
                }

                var psi = new System.Diagnostics.ProcessStartInfo("schtasks.exe", args)
                {
                    WindowStyle     = System.Diagnostics.ProcessWindowStyle.Hidden,
                    CreateNoWindow  = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                };

                using var p = System.Diagnostics.Process.Start(psi)!;
                p.WaitForExit(5000);

                if (p.ExitCode == 0)
                {
                    ShowBalloon(
                        enable ? "Auto-Start ativado" : "Auto-Start desativado",
                        enable
                            ? "O Configurador iniciará automaticamente com o Windows (via Agendador de Tarefas)."
                            : "O Configurador não iniciará mais automaticamente.",
                        ToolTipIcon.Info);
                    return true;
                }
                else
                {
                    var err = p.StandardError.ReadToEnd();
                    MessageBox.Show(
                        $"Não foi possível {(enable ? "criar" : "remover")} a tarefa do Agendador:\n{err}",
                        "Auto-Start", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return false;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Erro ao configurar Auto-Start:\n{ex.Message}",
                    "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // Balloon notification (bolha do tray)
        // ─────────────────────────────────────────────────────────────────────

        private void ShowBalloon(string title, string text, ToolTipIcon icon)
        {
            if (_trayIcon == null) return;
            _trayIcon.BalloonTipTitle = title;
            _trayIcon.BalloonTipText  = text;
            _trayIcon.BalloonTipIcon  = icon;
            _trayIcon.ShowBalloonTip(4000);
        }

        // ─────────────────────────────────────────────────────────────────────
        // InitializeComponent
        // ─────────────────────────────────────────────────────────────────────

        private void InitializeComponent()
        {
            var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
            Text            = $"Coliseu Sales — Worker Configurator v{version}";
            MinimumSize     = new Size(860, 760);
            Size            = new Size(1150, 860);
            StartPosition   = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.Sizable;
            MaximizeBox     = true;
            BackColor       = ColiseuColors.BgPage;
            Font            = new Font("Segoe UI", 9f);

            // Ícone da janela (taskbar) — usa o símbolo isolado
            if (_iconImage is Bitmap bmp)
            {
                try
                {
                    var resizedBmp = new Bitmap(bmp, 32, 32);
                    Icon = Icon.FromHandle(resizedBmp.GetHicon());
                }
                catch { }
            }

            var layout = new TableLayoutPanel
            {
                Dock        = DockStyle.Fill,
                RowCount    = 3,
                ColumnCount = 1,
                Padding     = Padding.Empty,
                Margin      = Padding.Empty,
            };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 100));  // header
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,   3));  // linha separadora azul
            layout.RowStyles.Add(new RowStyle(SizeType.Percent,  100));  // tabs

            layout.Controls.Add(BuildHeader(), 0, 0);

            // Linha separadora azul — substitui o Paint handler fragmentado
            layout.Controls.Add(new Panel
            {
                Dock      = DockStyle.Fill,
                BackColor = ColiseuColors.Blue,
            }, 0, 1);

            var tabs = new TabControl
            {
                Dock     = DockStyle.Fill,
                Font     = new Font("Segoe UI", 9f),
                Padding  = new Point(14, 6),
                Margin   = new Padding(0, 8, 0, 0),
            };
            tabs.TabPages.Add(BuildConfigTab());
            tabs.TabPages.Add(BuildMonitorTab());
            tabs.TabPages.Add(BuildLogTab());
            tabs.SelectedIndexChanged += (_, _) =>
            {
                if (string.IsNullOrEmpty(txtServiceSuffix.Text.Trim()))
                {
                    MessageBox.Show("Preencha o Nome da Empresa e salve as configurações antes de prosseguir.", "Aviso", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    tabs.SelectedIndex = 0; // force configurations tab
                    txtServiceSuffix.Focus();
                    return;
                }
                if (tabs.SelectedIndex == 1) StartMonitoring();
                else StopMonitoring();
            };
            layout.Controls.Add(tabs, 0, 2);

            Controls.Add(layout);

            // ── Comportamento de fechar/minimizar → vai para bandeja ──────────
            FormClosing += (_, e) =>
            {
                if (!_isQuitting)
                {
                    e.Cancel = true;
                    Hide();
                    ShowInTaskbar = false;
                    ShowBalloon("Coliseu Worker Monitor",
                        "Monitorando em segundo plano. Clique duplo no ícone para reabrir.",
                        ToolTipIcon.Info);
                }
                else
                {
                    StopMonitoring();
                    _trayIcon.Visible = false;
                }
            };

            Resize += (_, _) =>
            {
                if (WindowState == FormWindowState.Minimized)
                {
                    Hide();
                    ShowInTaskbar = false;
                }
            };

// ── Se iniciado com --minimized (boot do Windows) → não mostra janela ──
            Shown += async (_, _) =>
            {
                if (_startMinimized)
                {
                    if (string.IsNullOrEmpty(txtServiceSuffix.Text.Trim()))
                    {
                        ShowMainWindow();
                    }
                    else
                    {
                        Hide();
                        ShowInTaskbar = false;
                    }
                }
                // Auto-setup: instalar + iniciar Worker sem sobrescrever as configurações.
                // saveSettings=false garante que o appsettings.json existente seja preservado.
                await EnsureWorkerReadyAsync(saveSettings: false);
            };
        }

        // ─────────────────────────────────────────────────────────────────────
        // Header com logo Coliseu
        // ─────────────────────────────────────────────────────────────────────

        private Panel BuildHeader()
        {
            // Fundo branco — sem Paint handler (linha movida para o TableLayoutPanel)
            var header = new Panel
            {
                Dock      = DockStyle.Fill,
                BackColor = Color.White,
                Padding   = new Padding(0),
            };

            // Logo completo (coliseu sistemas)
            var logoPb = new PictureBox
            {
                Location  = new Point(14, 6),
                Size      = new Size(280, 88),
                SizeMode  = PictureBoxSizeMode.Zoom,
                BackColor = Color.White,
                Image     = _fullLogoImage,
            };
            header.Controls.Add(logoPb);

            // Divider vertical
            header.Controls.Add(new Panel
            {
                Location  = new Point(305, 14),
                Size      = new Size(1, 72),
                BackColor = ColiseuColors.Border,
            });

            // "Worker Configurator"
            header.Controls.Add(new Label
            {
                Text      = "Worker Configurator",
                Location  = new Point(320, 24),
                Size      = new Size(460, 28),
                Font      = new Font("Segoe UI", 13f, FontStyle.Bold),
                ForeColor = ColiseuColors.TextDark,
                BackColor = Color.Transparent,
            });
            header.Controls.Add(new Label
            {
                Text      = "Sincronização Firebird ↔ VPS",
                Location  = new Point(321, 54),
                Size      = new Size(460, 18),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextMid,
                BackColor = Color.Transparent,
            });

            return header;
        }

        // ─────────────────────────────────────────────────────────────────────
        // Aba 1: Configurações
        // ─────────────────────────────────────────────────────────────────────

        private TabPage BuildConfigTab()
        {
            var tab = new TabPage("⚙  Configurações") { BackColor = ColiseuColors.BgPage, Padding = new Padding(0) };
            var panel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(20, 18, 20, 18), BackColor = ColiseuColors.BgPage };
            tab.Controls.Add(panel);

            int y = 0;

            // Botão Desbloquear Edição
            btnUnlock = MakeButton("🔓  Desbloquear Edição", 0, y, 220, BtnUnlock_Click, primary: false);
            btnUnlock.Height = 36;
            btnUnlock.Font   = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            panel.Controls.Add(btnUnlock);
            y += 50;

            AddSection(panel, "Banco de Dados Firebird", y);
            y += 30;
            AddFormRow(panel, "Caminho do Banco:", out txtFirebirdDb, y, isPassword: false, hasButton: true,
                btnText: "Buscar...", btnAction: BtnBrowse_Click, actionBtn: out btnBrowse);
            y += 48;
            AddFormRow(panel, "Usuário Firebird:", out txtFirebirdUser, y);
            txtFirebirdUser.Text = "SYSDBA";
            y += 44;
            AddFormRow(panel, "Senha Firebird:", out txtFirebirdPass, y, isPassword: true);
            y += 44;

            // WireCrypt
            chkWireCrypt = new CheckBox
            {
                Text      = "Usar WireCrypt (encriptação de rede Firebird)",
                Location  = new Point(0, y),
                AutoSize  = true,
                Font      = new Font("Segoe UI", 9.5f),
                ForeColor = ColiseuColors.TextDark,
            };
            panel.Controls.Add(chkWireCrypt);
            y += 28;

            // Botão Preparar Banco — bootstrap de SPs/Views/Colunas
            var lblBootstrapStatus = new Label
            {
                Location  = new Point(240, y + 2),
                Size      = new Size(460, 20),
                Font      = new Font("Segoe UI", 8.5f, FontStyle.Italic),
                ForeColor = ColiseuColors.TextLight,
                Text      = "",
            };
            btnBootstrap = MakeButton("🔧  Preparar Banco", 0, y, 220,
                (_, _) => _ = BtnBootstrap_Click(lblBootstrapStatus), primary: false);
            btnBootstrap.Height = 36;
            btnBootstrap.Font   = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            panel.Controls.Add(btnBootstrap);
            panel.Controls.Add(lblBootstrapStatus);
            y += 48;

            AddSection(panel, "Chave Identificadora da Empresa", y);
            y += 30;
            AddFormRow(panel, "URL Identity:", out txtIdentityUrl, y);
            y += 44;
            AddFormRow(panel, "Chave:", out txtTenantId, y);
            txtTenantId.PlaceholderText = "00000000-0000-0000-0000-000000000000";
            y += 52;

            AddSection(panel, "⏱  Tarefas de Sincronismo", y);
            y += 30;
            AddFormRowNumeric(panel, "Catálogo e Dados (min):", out numCatalogSync, y, 1, 60);
            y += 44;
            AddFormRowNumeric(panel, "Pedidos e Clientes (seg):", out numOrderSync, y, 10, 300);
            y += 44;
            AddFormRowNumeric(panel, "Conexões Máximas (Pool):", out numMaxPoolSize, y, 5, 200);
            y += 44;
            AddFormRowNumeric(panel, "Tempo Limite Conexão (seg):", out numConnectionTimeout, y, 10, 300);
            y += 52;

            AddSection(panel, "Serviço Windows do Worker", y);
            y += 30;
            AddFormRow(panel, "Nome da Empresa:", out txtServiceSuffix, y);
            txtServiceSuffix.PlaceholderText = "Ex: Piveta, Filial2";
            y += 52;

            AddSection(panel, "APP de Força de Vendas (SALES)", y);
            y += 30;
            chkSalesEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização Força de Vendas",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = true,
            };
            chkSalesEnabled.CheckedChanged += (_, _) =>
            {
                txtVpsUrl.Enabled    = chkSalesEnabled.Checked;
                txtVpsApiKey.Enabled = chkSalesEnabled.Checked;
            };
            panel.Controls.Add(chkSalesEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtVpsUrl, y);
            y += 44;
            AddFormRow(panel, "API Key:", out txtVpsApiKey, y);
            y += 52;

            AddSection(panel, "🤖  Atendente do Futuro (WhatsApp)", y);
            y += 30;
            chkAtendenteEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização com o Atendente do Futuro",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkAtendenteEnabled.CheckedChanged += (_, _) =>
            {
                txtAtendenteUrl.Enabled    = chkAtendenteEnabled.Checked;
                txtAtendenteApiKey.Enabled = chkAtendenteEnabled.Checked;
            };
            panel.Controls.Add(chkAtendenteEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtAtendenteUrl, y);
            txtAtendenteUrl.PlaceholderText = "https://atendente.seudominio.com";
            txtAtendenteUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "API Key:", out txtAtendenteApiKey, y);
            txtAtendenteApiKey.Enabled = false;
            y += 58;

            AddSection(panel, "🔧  AutoCenter (Oficina Mecânica)", y);
            y += 30;
            chkAcEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização AutoCenter",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkAcEnabled.CheckedChanged += (_, _) =>
            {
                txtAcUrl.Enabled    = chkAcEnabled.Checked;
                txtAcApiKey.Enabled = chkAcEnabled.Checked;
            };
            panel.Controls.Add(chkAcEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtAcUrl, y);
            txtAcUrl.PlaceholderText = "http://localhost:3000";
            txtAcUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "Internal API Key:", out txtAcApiKey, y);
            y += 58;

            AddSection(panel, "📈  Coliseu Dash", y);
            y += 30;
            chkDashEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização Coliseu Dash",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkDashEnabled.CheckedChanged += (_, _) =>
            {
                txtDashUrl.Enabled    = chkDashEnabled.Checked;
                txtDashApiKey.Enabled = chkDashEnabled.Checked;
            };
            panel.Controls.Add(chkDashEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtDashUrl, y);
            txtDashUrl.PlaceholderText = "https://dashboard.coliseusistemas.com.br";
            txtDashUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "Internal API Key:", out txtDashApiKey, y);
            txtDashApiKey.Enabled = false;
            y += 58;

            // 🌐 Nexus
            AddSection(panel, "🌐  Nexus", y);
            y += 30;
            chkNexusEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização Nexus",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkNexusEnabled.CheckedChanged += (_, _) =>
            {
                txtNexusUrl.Enabled    = chkNexusEnabled.Checked;
                txtNexusApiKey.Enabled = chkNexusEnabled.Checked;
            };
            panel.Controls.Add(chkNexusEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtNexusUrl, y);
            txtNexusUrl.PlaceholderText = "https://nexus.coliseusistemas.com.br";
            txtNexusUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "Internal API Key:", out txtNexusApiKey, y);
            txtNexusApiKey.Enabled = false;
            y += 58;

            // 👁️ Vision
            AddSection(panel, "👁️  Vision", y);
            y += 30;
            chkVisionEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização Vision",
                Location  = new Point(0, y),
                Size      = new Size(400, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkVisionEnabled.CheckedChanged += (_, _) =>
            {
                txtVisionUrl.Enabled    = chkVisionEnabled.Checked;
                txtVisionApiKey.Enabled = chkVisionEnabled.Checked;
            };
            panel.Controls.Add(chkVisionEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtVisionUrl, y);
            txtVisionUrl.PlaceholderText = "https://vision.coliseusistemas.com.br";
            txtVisionUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "Internal API Key:", out txtVisionApiKey, y);
            txtVisionApiKey.Enabled = false;
            y += 58;

            AddSection(panel, "🛡️  Controle de Garantias", y);
            y += 30;
            chkGarantiasEnabled = new CheckBox
            {
                Text      = "Habilitar sincronização com Controle de Garantias",
                Location  = new Point(0, y),
                Size      = new Size(450, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = false,
            };
            chkGarantiasEnabled.CheckedChanged += (_, _) =>
            {
                txtGarantiasUrl.Enabled    = chkGarantiasEnabled.Checked;
                txtGarantiasApiKey.Enabled = chkGarantiasEnabled.Checked;
            };
            panel.Controls.Add(chkGarantiasEnabled);
            y += 30;
            AddFormRow(panel, "URL da API:", out txtGarantiasUrl, y);
            txtGarantiasUrl.PlaceholderText = "https://garantias.coliseusistemas.com.br";
            txtGarantiasUrl.Enabled = false;
            y += 44;
            AddFormRow(panel, "Internal API Key:", out txtGarantiasApiKey, y);
            txtGarantiasApiKey.Enabled = false;
            y += 58;

            // Checkbox visível com estado atual da tarefa agendada
            bool autoStartOn = IsAutoStartEnabled();
            chkAutoStart = new CheckBox
            {
                Text      = "Iniciar automaticamente com o Windows (via Agendador de Tarefas)",
                Location  = new Point(0, y),
                Size      = new Size(500, 22),
                Font      = new Font("Segoe UI", 9f),
                ForeColor = ColiseuColors.TextDark,
                Checked   = autoStartOn,
            };

            // Label informativo com status atual
            var lblAutoStatus = new Label
            {
                Text      = autoStartOn
                    ? "✅ Tarefa agendada ativa — o Configurador iniciará ao login"
                    : "⚪ Tarefa não agendada",
                Location  = new Point(22, y + 26),
                Size      = new Size(500, 16),
                Font      = new Font("Segoe UI", 7.5f, FontStyle.Italic),
                ForeColor = autoStartOn ? ColiseuColors.Success : ColiseuColors.TextLight,
            };

            chkAutoStart.CheckedChanged += (_, _) =>
            {
                bool ok = SetAutoStart(chkAutoStart.Checked);
                if (!ok)
                {
                    // Reverter visualmente se falhou
                    chkAutoStart.CheckedChanged -= null;
                    chkAutoStart.Checked = !chkAutoStart.Checked;
                }
                bool nowOn = IsAutoStartEnabled();
                lblAutoStatus.Text      = nowOn
                    ? "✅ Tarefa agendada ativa — o Configurador iniciará ao login"
                    : "⚪ Tarefa não agendada";
                lblAutoStatus.ForeColor = nowOn ? ColiseuColors.Success : ColiseuColors.TextLight;
            };

            panel.Controls.Add(chkAutoStart);
            panel.Controls.Add(lblAutoStatus);
            y += 58;

            btnSave = MakeButton("💾  Salvar e Aplicar", 0, y, 220, BtnSave_Click, primary: true);
            btnSave.Height = 42;
            btnSave.Font   = new Font("Segoe UI", 10f, FontStyle.Bold);
            panel.Controls.Add(btnSave);

            // Scroll support — config tab is now taller with Atendente section
            panel.AutoScroll = true;

            return tab;
        }

        // ─────────────────────────────────────────────────────────────────────
        // Bootstrap Firebird — verifica e cria objetos obrigatórios
        // ─────────────────────────────────────────────────────────────────────

        private async Task BtnBootstrap_Click(Label statusLabel)
        {
            var dbPathStr = txtFirebirdDb.Text.Trim();
            if (string.IsNullOrEmpty(dbPathStr))
            {
                MessageBox.Show("Preencha o caminho do banco Firebird antes de preparar.",
                    "Preparar Banco", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            var user = txtFirebirdUser.Text.Trim();
            var pass = txtFirebirdPass.Text.Trim();
            if (string.IsNullOrEmpty(user)) user = "SYSDBA";
            if (string.IsNullOrEmpty(pass)) pass = "masterkey";

            var (fbHost, fbPort, fbDatabase) = SettingsManager.ParseFirebirdPath(dbPathStr);

            var bootstrapper = new FirebirdBootstrapper(
                fbHost, fbPort, fbDatabase, user, pass, chkWireCrypt.Checked);

            statusLabel.Text = "⏳ Diagnosticando...";
            statusLabel.ForeColor = ColiseuColors.TextMid;

            try
            {
                // Fase 1: Diagnóstico
                var diagnosis = await bootstrapper.DiagnoseAsync();
                var missing = diagnosis.Count(i => i.Status == FirebirdBootstrapper.ItemStatus.Error);
                var requiresUpdate = diagnosis.Count(i => i.Status == FirebirdBootstrapper.ItemStatus.RequiresUpdate);
                var total = diagnosis.Count;

                if (missing == 0 && requiresUpdate == 0)
                {
                    statusLabel.Text = $"✅ Banco pronto — {total}/{total} objetos OK";
                    statusLabel.ForeColor = ColiseuColors.Success;
                    MessageBox.Show(
                        $"O banco Firebird possui todos os {total} objetos necessários.\n\n" +
                        "Nenhuma alteração é necessária.",
                        "Banco Pronto", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                // Pergunta ao usuário
                var msg = missing > 0 
                    ? $"Foram encontrados {missing} objeto(s) faltante(s) de {total} necessário(s)."
                    : $"Foram encontradas {requiresUpdate} atualização(ões) pendente(s) de procedures.";

                if (missing > 0 && requiresUpdate > 0)
                    msg = $"Foram encontrados {missing} objeto(s) faltante(s) e {requiresUpdate} atualização(ões) de {total} necessário(s).";

                var answer = MessageBox.Show(
                    $"{msg}\n\n" +
                    "Deseja aplicar as alterações no banco Firebird agora?",
                    "Preparar Banco", MessageBoxButtons.YesNo, MessageBoxIcon.Question);

                if (answer != DialogResult.Yes)
                {
                    statusLabel.Text = $"⚠ {missing + requiresUpdate} objetos pendentes";
                    statusLabel.ForeColor = ColiseuColors.Error;
                    return;
                }

                // Fase 2: Bootstrap
                statusLabel.Text = "⏳ Criando/Atualizando objetos...";
                var logLines = new List<string>();
                var progress = new Progress<string>(msg =>
                {
                    logLines.Add(msg);
                    statusLabel.Text = msg;
                });

                var results = await bootstrapper.BootstrapAsync(progress);

                var created = results.Count(r => r.Status == FirebirdBootstrapper.ItemStatus.Created);
                var updated = results.Count(r => r.Status == FirebirdBootstrapper.ItemStatus.RequiresUpdate);
                var errors  = results.Count(r => r.Status == FirebirdBootstrapper.ItemStatus.Error);
                var existed = results.Count(r => r.Status == FirebirdBootstrapper.ItemStatus.AlreadyExists);

                // Monta relatório detalhado
                var report = string.Join("\n", logLines);

                if (errors == 0)
                {
                    statusLabel.Text = $"✅ Banco preparado — {created} criados, {updated} atualizados";
                    statusLabel.ForeColor = ColiseuColors.Success;
                    MessageBox.Show(
                        $"Bootstrap concluído com sucesso!\n\n" +
                        $"  ✅ Já existiam: {existed}\n" +
                        $"  🔄 Atualizados: {updated}\n" +
                        $"  🔧 Criados: {created}\n" +
                        $"  ❌ Erros: {errors}\n\n" +
                        $"Detalhes:\n{report}",
                        "Banco Preparado", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    statusLabel.Text = $"⚠ Parcial — {created} criados, {errors} erros";
                    statusLabel.ForeColor = ColiseuColors.Error;
                    MessageBox.Show(
                        $"Bootstrap concluído com erros.\n\n" +
                        $"  ✅ Já existiam: {existed}\n" +
                        $"  🔄 Atualizados: {updated}\n" +
                        $"  🔧 Criados: {created}\n" +
                        $"  ❌ Erros: {errors}\n\n" +
                        $"Detalhes:\n{report}",
                        "Erros no Bootstrap", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
            catch (Exception ex)
            {
                statusLabel.Text = $"❌ Erro: {ex.Message}";
                statusLabel.ForeColor = ColiseuColors.Error;
                MessageBox.Show(
                    $"Erro ao conectar ao Firebird:\n\n{ex.Message}",
                    "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // Aba 2: Monitoramento — WebView2 dashboard
        // ─────────────────────────────────────────────────────────────────────

        private TabPage BuildMonitorTab()
        {
            var tab = new TabPage("📊  Monitoramento") { BackColor = ColiseuColors.MonitorBg };

            // Panel for the title
            var pnlTopTitle = new Panel { Dock = DockStyle.Top, Height = 40, BackColor = ColiseuColors.MonitorBg };
            var lblTopTitle = new Label
            {
                Text = "ENTIDADES SINCRONIZADAS",
                Location = new Point(10, 15),
                AutoSize = true,
                Font = new Font("Segoe UI", 11f, FontStyle.Bold),
                ForeColor = ColiseuColors.Success
            };
            pnlTopTitle.Controls.Add(lblTopTitle);
            tab.Controls.Add(pnlTopTitle);

            // SplitContainer responsivo para dividir os Cards e os Logs
            var split = new SplitContainer
            {
                Dock = DockStyle.Fill,
                Orientation = Orientation.Horizontal,
                SplitterDistance = 220, // Altura ideal padrão para duas fileiras completas de cards
                Panel1MinSize = 110,
                Panel2MinSize = 150,
                BackColor = ColiseuColors.MonitorBg
            };

            // Cards panel docked to Fill in Panel1
            _cardsPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                AutoScroll = true,
                Padding = new Padding(10),
                BackColor = ColiseuColors.MonitorBg,
                BorderStyle = BorderStyle.None
            };
            split.Panel1.Controls.Add(_cardsPanel);

            // Bottom Panel for Logs in Panel2
            var pnlLogs = new Panel { Dock = DockStyle.Fill, Padding = new Padding(10), BackColor = ColiseuColors.MonitorBg };
            var lblLogHeader = new Label
            {
                Text = "LOG EM TEMPO REAL",
                Dock = DockStyle.Top,
                Height = 25,
                Font = new Font("Segoe UI", 11f, FontStyle.Bold),
                ForeColor = ColiseuColors.Success
            };

            _monitorLogBox = new RichTextBox
            {
                Dock = DockStyle.Fill,
                BackColor = ColiseuColors.Terminal,
                ForeColor = ColiseuColors.TermText,
                Font = new Font("Consolas", 9f),
                ReadOnly = true,
                ScrollBars = RichTextBoxScrollBars.Vertical,
                BorderStyle = BorderStyle.FixedSingle
            };
            
            // Botões no rodapé dos logs
            var pnlLogActions = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 10, 0, 0), BackColor = ColiseuColors.MonitorBg };
            var btnForceSync = MakeButton("⚡ Forçar Sync Agora", 0, 10, 160, async (_, _) =>
            {
                try {
                    await _http.PostAsync($"{MonitorBase}/force-sync", null);
                    AppendLog("⚡ Sync forçado solicitado.");
                } catch { }
            }, primary: true);
            var btnClearLog = MakeButton("✕ Limpar Log", 170, 10, 120, (_, _) => _monitorLogBox.Clear(), primary: false);
            pnlLogActions.Controls.Add(btnForceSync);
            pnlLogActions.Controls.Add(btnClearLog);
            
            pnlLogs.Controls.Add(_monitorLogBox);
            pnlLogs.Controls.Add(lblLogHeader);
            pnlLogs.Controls.Add(pnlLogActions);

            // Garante Z-order correto dos controles de log
            lblLogHeader.BringToFront();
            pnlLogActions.BringToFront();
            _monitorLogBox.BringToFront();
            
            split.Panel2.Controls.Add(pnlLogs);
            tab.Controls.Add(split);

            // Garante Z-order do split e do título
            pnlTopTitle.BringToFront();
            split.BringToFront();

            return tab;
        }



        // ─────────────────────────────────────────────────────────────────────
        // Monitoramento — lógica
        // ─────────────────────────────────────────────────────────────────────

        private void StartMonitoring()
        {

            _sseCts    = new CancellationTokenSource();
            _pollTimer = new System.Windows.Forms.Timer { Interval = 5000 };
            _pollTimer.Tick += async (_, _) =>
            {
                await RefreshStatusAsync();
                await CheckAndAutoRestartWorkerAsync();
            };
            _pollTimer.Start();
            _ = RefreshStatusAsync();
            _ = StartSseAsync(_sseCts.Token);
        }

        private void StopMonitoring()
        {
            _pollTimer?.Stop();
            _pollTimer?.Dispose();
            _sseCts.Cancel();
        }

        /// <summary>
        /// Verifica se o serviço Worker está parado e o reinicia automaticamente.
        /// Exibe balloon notification ao reiniciar.
        /// </summary>
        private Task CheckAndAutoRestartWorkerAsync()
        {
            try
            {
                using var sc = new ServiceController(CurrentWorkerServiceName);
                if (sc.Status == ServiceControllerStatus.Stopped ||
                    sc.Status == ServiceControllerStatus.StopPending)
                {
                    sc.Start();
                    sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(10));
                    ShowBalloon("⚠ Worker reiniciado automaticamente",
                        "O serviço Coliseu Sales Worker estava parado e foi reiniciado.",
                        ToolTipIcon.Warning);
                    UI(() => AppendLog("[AUTO-RESTART] Worker estava parado — reiniciado automaticamente."));
                }
            }
            catch (InvalidOperationException)
            {
                // Serviço não instalado — ignorar silenciosamente
            }
            catch (Exception ex)
            {
                UI(() => AppendLog($"[AUTO-RESTART] Erro ao tentar reiniciar Worker: {ex.Message}"));
            }
            return Task.CompletedTask;
        }

        private async Task RefreshStatusAsync()
        {
            try
            {
                var json = await _http.GetStringAsync($"{MonitorBase}/status");
                using var doc = JsonDocument.Parse(json);
                var ents = new List<(string, int, string?, bool, string?)>();
                foreach (var e in doc.RootElement.GetProperty("entities").EnumerateArray())
                {
                    ents.Add((
                        e.GetProperty("entity").GetString() ?? "",
                        e.GetProperty("count").GetInt32(),
                        e.TryGetProperty("lastSync", out var ls) && ls.ValueKind != JsonValueKind.Null ? ls.GetString() : null,
                        e.GetProperty("success").GetBoolean(),
                        e.TryGetProperty("error", out var er) && er.ValueKind != JsonValueKind.Null ? er.GetString() : null
                    ));
                }
                UI(() =>
                {
                    SetStatus(true);
                    RenderCards(ents);
                });
            }
            catch
            {
                UI(() => SetStatus(false));
            }
        }

        private void SetStatus(bool online)
        {
            // Status agora é gerenciado pelo dashboard.html via polling JS
            // (método mantido para compatibilidade com RefreshStatusAsync)
        }

        // Mapeamento de nomes da API (inglês) para Português com ícone
        private static (string label, string icon) EntityDisplay(string entity) => entity.ToLowerInvariant() switch
        {
            "sellers"          => ("Vendedores",         "👤"),
            "catalog"          => ("Catálogo",            "📦"),
            "customers"        => ("Clientes",            "🏢"),
            "salesrankings"    => ("Ranking de Vendas",  "🏆"),
            "performance"      => ("Desempenho",          "📊"),
            "financials"       => ("Financeiro",          "💰"),
            "paymentspecies"   => ("Espécies de Pgto",   "🏷️"),
            "paymentcondition" => ("Cond. Pagamento",    "📅"),
            "paymentconditions"=> ("Cond. Pagamento",    "📅"),
            "natureza"         => ("Natureza Op.",        "📌"),
            _                  => (entity,               "🔄"),
        };

        private void RenderCards(List<(string entity, int count, string? sync, bool ok, string? err)> items)
        {
            if (_cardsPanel == null) return;
            
            _cardsPanel.SuspendLayout();
            _cardsPanel.Controls.Clear();

            // Ordena os itens por módulo (Core -> Dash -> Nexus -> Vision -> Garantias) e depois por nome da entidade
            var sortedItems = items.OrderBy(item =>
            {
                string name = item.entity.ToLowerInvariant();
                if (name.StartsWith("dash_")) return 1;
                if (name.StartsWith("nexus_")) return 2;
                if (name.StartsWith("vision_")) return 3;
                if (name.StartsWith("garantias_") || name.StartsWith("garantias")) return 4;
                return 0; // Core
            }).ThenBy(item => item.entity).ToList();

            foreach (var item in sortedItems)
            {
                var info = EntityDisplay(item.entity);
                Color statusColor = item.ok ? ColiseuColors.Success : ColiseuColors.Error;
                
                // Determina a cor do módulo baseando-se na entidade
                Color moduleColor = ColiseuColors.CoreModule;
                string entLower = item.entity.ToLowerInvariant();
                if (entLower.StartsWith("nexus_"))
                    moduleColor = ColiseuColors.NexusModule;
                else if (entLower.StartsWith("vision_"))
                    moduleColor = ColiseuColors.VisionModule;
                else if (entLower.StartsWith("dash_"))
                    moduleColor = ColiseuColors.DashModule;
                else if (entLower.StartsWith("garantias_") || entLower.StartsWith("garantias"))
                    moduleColor = ColiseuColors.GarantiasModule;

                var card = new Panel
                {
                    Width = 175,
                    Height = 90,
                    BackColor = ColiseuColors.MonitorCard,
                    Margin = new Padding(5),
                    Padding = new Padding(8)
                };
                
                // Border com destaque lateral de 4px na cor do módulo correspondente
                DrawCardBorder(card, ColiseuColors.MonitorLine, moduleColor);

                // Icon 
                var lblIcon = new Label
                {
                    Text = info.icon,
                    Location = new Point(12, 10), // Deslocado de 8 para 12
                    AutoSize = true,
                    Font = new Font("Segoe UI", 10f),
                    ForeColor = moduleColor // Ícone na cor do módulo
                };
                card.Controls.Add(lblIcon);

                // Title (Subtitle in old layout)
                var lblTitle = new Label
                {
                    Text = info.label,
                    Location = new Point(46, 11), // Deslocado de 42 para 46
                    AutoSize = true,
                    Font = new Font("Segoe UI", 8.5f),
                    ForeColor = ColiseuColors.MonitorText
                };
                card.Controls.Add(lblTitle);

                // Count (BIG number)
                var lblCount = new Label
                {
                    Text = $"{item.count:N0}",
                    Location = new Point(12, 32), // Deslocado de 8 para 12
                    AutoSize = true,
                    Font = new Font("Segoe UI", 16f, FontStyle.Bold),
                    ForeColor = ColiseuColors.MonitorText
                };
                card.Controls.Add(lblCount);

                // Sync info (Subtitle with time)
                var syncText = string.IsNullOrEmpty(item.err) 
                    ? (item.sync != null ? $"✓ {item.sync}" : "Aguardando...") 
                    : item.err;
                
                if (item.err == "Desativado")
                {
                    statusColor = Color.Gray;
                    syncText = "⛔ Desativado";
                }
                else if (item.err != null && item.err.Contains("Aguardando"))
                {
                    statusColor = Color.FromArgb(245, 158, 11); // Yellow/Orange
                }
                
                var lblSync = new Label
                {
                    Text = syncText,
                    Location = new Point(12, 65), // Deslocado de 8 para 12
                    Size = new Size(156, 16), // Ajustado largura para caber no card com a margem
                    Font = new Font("Segoe UI", 7.5f),
                    ForeColor = statusColor,
                    AutoEllipsis = true
                };
                card.Controls.Add(lblSync);

                _cardsPanel.Controls.Add(card);
            }
            
            _cardsPanel.ResumeLayout();
        }


        private static void DrawCardBorder(Control c, Color accent, Color moduleColor)
        {
            c.Paint += (_, e) =>
            {
                // Borda cinza geral
                using var pen = new Pen(Color.FromArgb(50, accent), 1);
                e.Graphics.DrawRectangle(pen, 0, 0, c.Width - 1, c.Height - 1);

                // Barra de destaque lateral na cor do módulo (esquerda)
                using var brush = new SolidBrush(moduleColor);
                e.Graphics.FillRectangle(brush, 0, 0, 4, c.Height);
            };
        }

        private static void RoundPanel(Panel p, int radius)
        {
            p.Paint += (_, e) =>
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using var brush = new SolidBrush(p.BackColor);
                using var path  = new GraphicsPath();
                path.AddEllipse(0, 0, p.Width, p.Height);
                e.Graphics.FillPath(brush, path);
                p.Region = new Region(path);
            };
        }

        private async Task StartSseAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    using var resp = await _http.GetAsync(
                        $"{MonitorBase}/logs",
                        HttpCompletionOption.ResponseHeadersRead, ct);
                    using var stream = await resp.Content.ReadAsStreamAsync(ct);
                    using var reader = new StreamReader(stream);

                    await Task.Run(async () =>
                    {
                        while (!ct.IsCancellationRequested)
                        {
                            var line = await reader.ReadLineAsync();
                            if (line == null) break;
                            if (!line.StartsWith("data:")) continue;
                            var msg = line[5..].Trim();
                            UI(() => AppendLog(msg));
                        }
                    }, ct);
                }
                catch (OperationCanceledException) { break; }
                catch { await Task.Delay(5000, CancellationToken.None); }
            }
        }

        private void AppendLog(string msg)
        {
            var line = $"[{DateTime.Now:HH:mm:ss}] {msg}\n";
            var lower = msg.ToLowerInvariant();
            Color color;
            if (lower.Contains("erro") || lower.Contains("error") ||
                lower.Contains("falha") || lower.Contains("id=0") || lower.Contains("⚠"))
            {
                color = Color.FromArgb(255, 90, 90);
            }
            else if (lower.Contains("warn") || lower.Contains("⚙"))
            {
                color = Color.FromArgb(255, 210, 80);
            }
            else
            {
                if (lower.Contains("[nexus]") || lower.Contains("nexus:") || lower.Contains("nexus_"))
                    color = ColiseuColors.NexusModule;
                else if (lower.Contains("[vision]") || lower.Contains("vision:") || lower.Contains("vision_"))
                    color = ColiseuColors.VisionModule;
                else if (lower.Contains("[dash]") || lower.Contains("dash:") || lower.Contains("dash_"))
                    color = ColiseuColors.DashModule;
                else if (lower.Contains("[garantias]") || lower.Contains("garantias:") || lower.Contains("garantias_"))
                    color = ColiseuColors.GarantiasModule;
                else if (lower.Contains("vendedores") || lower.Contains("catálogo") || lower.Contains("desempenho") || 
                         lower.Contains("financeiro") || lower.Contains("cond. pagamento") || lower.Contains("espécies de pgto") ||
                         lower.Contains("[core]") || lower.Contains("core:") || lower.Contains("força de vendas"))
                    color = ColiseuColors.CoreModule;
                else if (lower.Contains("✓") || lower.Contains("sincronizado") || lower.Contains("ok"))
                    color = Color.FromArgb(80, 230, 130);
                else
                    color = Color.FromArgb(200, 210, 220);
            }

            // Grava na aba Logs nativa principal
            if (_logBox != null && !_logPause)
            {
                _logBox.SuspendLayout();
                _logBox.SelectionStart  = _logBox.TextLength;
                _logBox.SelectionLength = 0;
                _logBox.SelectionColor  = color;
                _logBox.AppendText(line);
                const int MaxLines = 2000;
                if (_logBox.Lines.Length > MaxLines)
                {
                    var del = string.Join("\n", _logBox.Lines.Take(_logBox.Lines.Length - MaxLines)) + "\n";
                    _logBox.Select(0, del.Length);
                    _logBox.SelectedText = string.Empty;
                }
                _logBox.SelectionStart = _logBox.TextLength;
                _logBox.ResumeLayout();
                _logBox.ScrollToCaret();
            }

            // Grava também na aba de monitoramento
            if (_monitorLogBox != null && !_logPause)
            {
                _monitorLogBox.SuspendLayout();
                _monitorLogBox.SelectionStart  = _monitorLogBox.TextLength;
                _monitorLogBox.SelectionLength = 0;
                _monitorLogBox.SelectionColor  = color;
                _monitorLogBox.AppendText(line);
                const int MaxLines = 2000;
                if (_monitorLogBox.Lines.Length > MaxLines)
                {
                    var del = string.Join("\n", _monitorLogBox.Lines.Take(_monitorLogBox.Lines.Length - MaxLines)) + "\n";
                    _monitorLogBox.Select(0, del.Length);
                    _monitorLogBox.SelectedText = string.Empty;
                }
                _monitorLogBox.SelectionStart = _monitorLogBox.TextLength;
                _monitorLogBox.ResumeLayout();
                _monitorLogBox.ScrollToCaret();
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // Aba 3: Logs nativos — sem WebView2, lê do SSE stream
        // ─────────────────────────────────────────────────────────────────────

        private TabPage BuildLogTab()
        {
            var tab = new TabPage("📋  Logs") { BackColor = ColiseuColors.Terminal };

            // Toolbar superior
            var toolbar = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 38,
                BackColor = Color.FromArgb(25, 30, 45),
                Padding   = new Padding(6, 4, 6, 4),
            };

            var btnClear = new Button
            {
                Text      = "✕  Limpar",
                Location  = new Point(6, 5),
                Size      = new Size(90, 28),
                FlatStyle = FlatStyle.Flat,
                ForeColor = ColiseuColors.TextLight,
                BackColor = Color.FromArgb(50, 55, 75),
                Font      = new Font("Segoe UI", 8.5f),
                Cursor    = Cursors.Hand,
            };
            btnClear.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 110);
            btnClear.Click += (_, _) => _logBox.Clear();

            var chkPause = new CheckBox
            {
                Text      = "⏸  Pausar scroll",
                Location  = new Point(106, 8),
                AutoSize  = true,
                ForeColor = ColiseuColors.TextLight,
                Font      = new Font("Segoe UI", 8.5f),
                Cursor    = Cursors.Hand,
            };
            chkPause.CheckedChanged += (_, _) => _logPause = chkPause.Checked;

            var lblInfo = new Label
            {
                Text      = "Os logs do Worker aparecem aqui em tempo real.",
                Location  = new Point(260, 10),
                AutoSize  = true,
                ForeColor = ColiseuColors.TextLight,
                Font      = new Font("Segoe UI", 8f),
            };

            toolbar.Controls.AddRange(new Control[] { btnClear, chkPause, lblInfo });

            // RichTextBox principal
            _logBox = new RichTextBox
            {
                Dock            = DockStyle.Fill,
                BackColor       = ColiseuColors.Terminal,
                ForeColor       = ColiseuColors.TermText,
                Font            = new Font("Cascadia Mono", 9f, FontStyle.Regular),
                ReadOnly        = true,
                WordWrap        = false,
                ScrollBars      = RichTextBoxScrollBars.Both,
                BorderStyle     = BorderStyle.None,
                Padding         = new Padding(8),
            };

            _logBox.AppendText("Aguardando logs do Worker...\n");

            tab.Controls.Add(_logBox);
            tab.Controls.Add(toolbar);
            return tab;
        }

        private async void BtnForceSync_Click(object? sender, EventArgs e)
        {
            // Delegado ao botão no dashboard HTML (forceSync())
            // Este handler é mantido como fallback se HTML não estiver pronto
            try
            {
                await _http.PostAsync($"{MonitorBase}/force-sync", null);
                AppendLog($"⚡ Sync forçado solicitado.");
            }
            catch
            {
                AppendLog($"✗ Falha — Worker offline?");
            }
        }

        private void UI(Action a) { if (InvokeRequired) Invoke(a); else a(); }

        // ─────────────────────────────────────────────────────────────────────
        // Segurança e Bloqueio de Edição
        // ─────────────────────────────────────────────────────────────────────

        private string ShowPasswordDialog()
        {
            using (var prompt = new Form())
            {
                prompt.Width = 320;
                prompt.Height = 160;
                prompt.FormBorderStyle = FormBorderStyle.FixedDialog;
                prompt.Text = "Desbloquear Edição";
                prompt.StartPosition = FormStartPosition.CenterParent;
                prompt.MaximizeBox = false;
                prompt.MinimizeBox = false;
                prompt.BackColor = ColiseuColors.BgPage;

                var textLabel = new Label() 
                { 
                    Left = 16, 
                    Top = 16, 
                    Width = 280, 
                    Text = "Digite a Senha Mestra:", 
                    Font = new Font("Segoe UI", 9.5f),
                    ForeColor = ColiseuColors.TextDark 
                };
                var textBox = new TextBox() 
                { 
                    Left = 16, 
                    Top = 40, 
                    Width = 272, 
                    UseSystemPasswordChar = true, 
                    Font = new Font("Segoe UI", 10f),
                    BorderStyle = BorderStyle.FixedSingle
                };
                var confirmation = MakeButton("Confirmar", 104, 80, 90, (sender, e) => { prompt.DialogResult = DialogResult.OK; prompt.Close(); }, primary: true);
                var cancel = MakeButton("Cancelar", 200, 80, 90, (sender, e) => { prompt.DialogResult = DialogResult.Cancel; prompt.Close(); }, primary: false);

                prompt.Controls.Add(textLabel);
                prompt.Controls.Add(textBox);
                prompt.Controls.Add(confirmation);
                prompt.Controls.Add(cancel);
                prompt.AcceptButton = confirmation;
                prompt.CancelButton = cancel;

                return prompt.ShowDialog(this) == DialogResult.OK ? textBox.Text : string.Empty;
            }
        }

        private void BtnUnlock_Click(object? sender, EventArgs e)
        {
            var pass = ShowPasswordDialog();
            if (pass == "98683818")
            {
                SetFieldsLockState(false);
                btnUnlock.Text = "🔓  Edição Desbloqueada";
                btnUnlock.Enabled = false;
                ShowToast("🔓  Formulário desbloqueado para edição.");
            }
            else if (!string.IsNullOrEmpty(pass))
            {
                MessageBox.Show("Senha incorreta. Acesso negado.", "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void SetFieldsLockState(bool isLocked)
        {
            _isLocked = isLocked;

            // TextBoxes
            txtFirebirdDb.Enabled = !isLocked;
            txtFirebirdUser.Enabled = !isLocked;
            txtFirebirdPass.Enabled = !isLocked;
            txtIdentityUrl.Enabled = !isLocked;
            txtTenantId.Enabled = !isLocked;
            txtServiceSuffix.Enabled = !isLocked;

            // CheckBoxes
            chkWireCrypt.Enabled = !isLocked;
            chkSalesEnabled.Enabled = !isLocked;
            chkAtendenteEnabled.Enabled = !isLocked;
            chkAcEnabled.Enabled = !isLocked;
            chkDashEnabled.Enabled = !isLocked;
            chkNexusEnabled.Enabled = !isLocked;
            chkVisionEnabled.Enabled = !isLocked;
            chkGarantiasEnabled.Enabled = !isLocked;

            // NumericUpDowns
            numCatalogSync.Enabled = !isLocked;
            numOrderSync.Enabled = !isLocked;
            numMaxPoolSize.Enabled = !isLocked;
            numConnectionTimeout.Enabled = !isLocked;

            // Buttons
            if (btnBrowse != null) btnBrowse.Enabled = !isLocked;
            if (btnBootstrap != null) btnBootstrap.Enabled = !isLocked;
            if (btnSave != null) btnSave.Enabled = !isLocked;
            if (chkAutoStart != null) chkAutoStart.Enabled = !isLocked;

            // Conditional textboxes for sub-modules
            if (isLocked)
            {
                txtVpsUrl.Enabled = false;
                txtVpsApiKey.Enabled = false;
                txtAtendenteUrl.Enabled = false;
                txtAtendenteApiKey.Enabled = false;
                txtAcUrl.Enabled = false;
                txtAcApiKey.Enabled = false;
                txtDashUrl.Enabled = false;
                txtDashApiKey.Enabled = false;
                txtNexusUrl.Enabled = false;
                txtNexusApiKey.Enabled = false;
                txtVisionUrl.Enabled = false;
                txtVisionApiKey.Enabled = false;
                txtGarantiasUrl.Enabled = false;
                txtGarantiasApiKey.Enabled = false;
            }
            else
            {
                txtVpsUrl.Enabled = chkSalesEnabled.Checked;
                txtVpsApiKey.Enabled = chkSalesEnabled.Checked;
                txtAtendenteUrl.Enabled = chkAtendenteEnabled.Checked;
                txtAtendenteApiKey.Enabled = chkAtendenteEnabled.Checked;
                txtAcUrl.Enabled = chkAcEnabled.Checked;
                txtAcApiKey.Enabled = chkAcEnabled.Checked;
                txtDashUrl.Enabled = chkDashEnabled.Checked;
                txtDashApiKey.Enabled = chkDashEnabled.Checked;
                txtNexusUrl.Enabled = chkNexusEnabled.Checked;
                txtNexusApiKey.Enabled = chkNexusEnabled.Checked;
                txtVisionUrl.Enabled = chkVisionEnabled.Checked;
                txtVisionApiKey.Enabled = chkVisionEnabled.Checked;
                txtGarantiasUrl.Enabled = chkGarantiasEnabled.Checked;
                txtGarantiasApiKey.Enabled = chkGarantiasEnabled.Checked;
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // Configurações — lógica
        // ─────────────────────────────────────────────────────────────────────

        private void LoadSettings()
        {
            // Preenche com os defaults de produção
            txtFirebirdDb.Text   = Defaults.FirebirdDb;
            txtFirebirdUser.Text = "SYSDBA";
            txtFirebirdPass.Text = "masterkey";
            txtVpsUrl.Text       = "https://licencas.coliseusistemas.com.br";
            txtVpsApiKey.Text    = Defaults.VpsApiKey;
            txtIdentityUrl.Text  = "https://adminlicencas.coliseusistemas.com.br";
            txtTenantId.Text     = "";
            txtServiceSuffix.Text = "";
            
            // Preenche com os defaults de outras APIs
            txtAtendenteUrl.Text = "https://atendente.seudominio.com";
            txtAcUrl.Text        = "https://autocenter.coliseusistemas.com.br";
            txtDashUrl.Text      = "https://dashboard.coliseusistemas.com.br";
            txtNexusUrl.Text     = "https://nexus.coliseusistemas.com.br";
            txtVisionUrl.Text    = "https://vision.coliseusistemas.com.br";
            txtGarantiasUrl.Text = "https://garantias.coliseusistemas.com.br";

            // Sobrescreve com o que estiver salvo no appsettings (se não for placeholder)
            try
            {
                var s = _settings.ReadSettings();

                // Reconstruir a string de exibição do Firebird a partir dos campos separados
                // (Host/Port/Database) que UpdateSettings grava desde a correção do bug.
                // Formato para exibição: "host/port:database" ou "host:database" ou só "database"
                var fbHost = TryGet(s, "Firebird", "Host");
                var fbPort = TryGet(s, "Firebird", "Port");
                var fbDb   = TryGet(s, "Firebird", "Database");
                if (!string.IsNullOrEmpty(fbHost) && fbHost != "localhost" && !string.IsNullOrEmpty(fbDb))
                {
                    // Remoto: reconstroi "host/port:database" ou "host:database"
                    var displayStr = (!string.IsNullOrEmpty(fbPort) && fbPort != "3050")
                        ? $"{fbHost}/{fbPort}:{fbDb}"
                        : $"{fbHost}:{fbDb}";
                    txtFirebirdDb.Text = displayStr;
                }
                else
                {
                    // Local: usa só o Database (caminho ou alias)
                    OverrideIfReal(ref txtFirebirdDb, fbDb);
                }

                // WireCrypt
                var wc = TryGet(s, "Firebird", "WireCrypt");
                chkWireCrypt.Checked = string.Equals(wc, "True", StringComparison.OrdinalIgnoreCase)
                                    || string.Equals(wc, "true", StringComparison.OrdinalIgnoreCase);


                OverrideIfReal(ref txtFirebirdUser,  TryGet(s, "Firebird",    "User"));
                OverrideIfReal(ref txtFirebirdPass,  TryGet(s, "Firebird",    "Password"));
                var vpsEnabledStr = TryGet(s, "VpsApi", "Enabled");
                chkSalesEnabled.Checked = string.IsNullOrEmpty(vpsEnabledStr)
                                       || string.Equals(vpsEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(vpsEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtVpsUrl,        TryGet(s, "VpsApi",      "BaseUrl"));
                OverrideIfReal(ref txtVpsApiKey,     TryGet(s, "VpsApi",      "ApiKey"));
                txtVpsUrl.Enabled    = chkSalesEnabled.Checked;
                txtVpsApiKey.Enabled = chkSalesEnabled.Checked;
                OverrideIfReal(ref txtIdentityUrl,   TryGet(s, "IdentityApi", "BaseUrl"));
                var tid = TryGet(s, "IdentityApi", "TenantId");
                if (!string.IsNullOrWhiteSpace(tid) && tid != "00000000-0000-0000-0000-000000000000")
                    txtTenantId.Text = tid;

                // Worker
                var strCat = TryGet(s, "Worker", "CatalogSyncIntervalMinutes");
                var strOrd = TryGet(s, "Worker", "OrderSyncIntervalSeconds");
                numCatalogSync.Value = int.TryParse(strCat, out var cat) && cat > 0 ? Math.Min(cat, 60) : 5;
                numOrderSync.Value   = int.TryParse(strOrd, out var ord) && ord >= 10 ? Math.Min(ord, 300) : 30;

                // Firebird pool settings
                var strPoolSize = TryGet(s, "Firebird", "MaxPoolSize");
                var strTimeout = TryGet(s, "Firebird", "ConnectionTimeout");
                numMaxPoolSize.Value = int.TryParse(strPoolSize, out var poolSize) && poolSize >= 5 && poolSize <= 200 ? poolSize : 30;
                numConnectionTimeout.Value = int.TryParse(strTimeout, out var timeout) && timeout >= 10 && timeout <= 300 ? timeout : 60;
                
                var strSuffix = TryGet(s, "Worker", "ServiceSuffix");
                txtServiceSuffix.Text = strSuffix ?? "";

                // Atendente do Futuro
                var atendenteEnabled = TryGet(s, "AtendenteApi", "Enabled");
                chkAtendenteEnabled.Checked = string.Equals(atendenteEnabled, "True", StringComparison.OrdinalIgnoreCase)
                                           || string.Equals(atendenteEnabled, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtAtendenteUrl,    TryGet(s, "AtendenteApi", "BaseUrl"));
                OverrideIfReal(ref txtAtendenteApiKey, TryGet(s, "AtendenteApi", "ApiKey"));
                txtAtendenteUrl.Enabled    = chkAtendenteEnabled.Checked;
                txtAtendenteApiKey.Enabled = chkAtendenteEnabled.Checked;

                // AutoCenter
                var acEnabledStr = TryGet(s, "AutoCenterApi", "Enabled");
                chkAcEnabled.Checked = string.Equals(acEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(acEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtAcUrl,    TryGet(s, "AutoCenterApi", "BaseUrl"));
                OverrideIfReal(ref txtAcApiKey, TryGet(s, "AutoCenterApi", "InternalApiKey"));
                txtAcUrl.Enabled    = chkAcEnabled.Checked;
                txtAcApiKey.Enabled = chkAcEnabled.Checked;

                // Coliseu Dash
                var dashEnabledStr = TryGet(s, "DashboardApi", "Enabled");
                chkDashEnabled.Checked = string.Equals(dashEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(dashEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtDashUrl,    TryGet(s, "DashboardApi", "BaseUrl"));
                OverrideIfReal(ref txtDashApiKey, TryGet(s, "DashboardApi", "InternalApiKey"));
                txtDashUrl.Enabled    = chkDashEnabled.Checked;
                txtDashApiKey.Enabled = chkDashEnabled.Checked;

                // Nexus
                var nexusEnabledStr = TryGet(s, "NexusApi", "Enabled");
                chkNexusEnabled.Checked = string.Equals(nexusEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(nexusEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtNexusUrl,    TryGet(s, "NexusApi", "BaseUrl"));
                OverrideIfReal(ref txtNexusApiKey, TryGet(s, "NexusApi", "InternalApiKey"));
                txtNexusUrl.Enabled    = chkNexusEnabled.Checked;
                txtNexusApiKey.Enabled = chkNexusEnabled.Checked;

                // Vision
                var visionEnabledStr = TryGet(s, "VisionApi", "Enabled");
                chkVisionEnabled.Checked = string.Equals(visionEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(visionEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtVisionUrl,    TryGet(s, "VisionApi", "BaseUrl"));
                OverrideIfReal(ref txtVisionApiKey, TryGet(s, "VisionApi", "InternalApiKey"));
                txtVisionUrl.Enabled    = chkVisionEnabled.Checked;
                txtVisionApiKey.Enabled = chkVisionEnabled.Checked;

                // Controle de Garantias
                var garantiasEnabledStr = TryGet(s, "GarantiasApi", "Enabled");
                chkGarantiasEnabled.Checked = string.Equals(garantiasEnabledStr, "True", StringComparison.OrdinalIgnoreCase)
                                       || string.Equals(garantiasEnabledStr, "true", StringComparison.OrdinalIgnoreCase);
                OverrideIfReal(ref txtGarantiasUrl,    TryGet(s, "GarantiasApi", "BaseUrl"));
                OverrideIfReal(ref txtGarantiasApiKey, TryGet(s, "GarantiasApi", "InternalApiKey"));
                txtGarantiasUrl.Enabled    = chkGarantiasEnabled.Checked;
                txtGarantiasApiKey.Enabled = chkGarantiasEnabled.Checked;
            }
            catch { }
            SetFieldsLockState(true);
        }

        private static void OverrideIfReal(ref TextBox tb, string val)
        {
            // Aceita qualquer valor não vazio e não-placeholder — inclusive URLs de produção
            if (!string.IsNullOrWhiteSpace(val) && val != "CONFIGURE_AQUI")
                tb.Text = val;
        }

        private static void OverrideIfReal(ref ComboBox cb, string val)
        {
            if (!string.IsNullOrWhiteSpace(val) && val != "CONFIGURE_AQUI")
                cb.Text = val;
        }

        private static string TryGet(JsonElement root, string section, string key)
        {
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object) return "";
            if (root.TryGetProperty(section, out var sec) && sec.TryGetProperty(key, out var val))
            {
                // Suporta bool, int e string sem lançar exceção
                return val.ValueKind switch
                {
                    System.Text.Json.JsonValueKind.String  => val.GetString() ?? "",
                    System.Text.Json.JsonValueKind.Number  => val.GetRawText(),
                    System.Text.Json.JsonValueKind.True    => "True",
                    System.Text.Json.JsonValueKind.False   => "False",
                    _                                      => "",
                };
            }
            return "";
        }

        private void BtnSave_Click(object? sender, EventArgs e)
        {
            try
            {
                var suffix = txtServiceSuffix.Text.Trim();
                if (string.IsNullOrEmpty(suffix))
                {
                    MessageBox.Show("O campo Nome da Empresa é obrigatório.", "Erro de Validação", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    txtServiceSuffix.Focus();
                    return;
                }
                if (!System.Text.RegularExpressions.Regex.IsMatch(suffix, "^[a-zA-Z0-9_-]+$"))
                {
                    MessageBox.Show("O campo Nome da Empresa deve conter apenas letras, números, hífen (-) ou sublinhado (_). Espaços e outros caracteres especiais não são permitidos.", "Erro de Validação", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    txtServiceSuffix.Focus();
                    return;
                }
                // Salva appsettings.json na pasta do Worker
                _settings.UpdateSettings(
                    txtFirebirdDb.Text.Trim(),
                    txtFirebirdUser.Text.Trim(),
                    txtFirebirdPass.Text,         // não faz Trim() na senha — espaços são válidos
                    txtVpsUrl.Text.Trim(),
                    txtVpsApiKey.Text.Trim(),
                    txtIdentityUrl.Text.Trim(),
                    txtTenantId.Text.Trim(),
                    (int)numCatalogSync.Value,
                    (int)numOrderSync.Value,
                    (int)numMaxPoolSize.Value,
                    (int)numConnectionTimeout.Value,
                    chkAtendenteEnabled.Checked,
                    txtAtendenteUrl.Text.Trim(),
                    txtAtendenteApiKey.Text.Trim(),
                    chkAcEnabled.Checked,
                    txtAcUrl.Text.Trim(),
                    txtAcApiKey.Text.Trim(),
                    chkDashEnabled.Checked,
                    txtDashUrl.Text.Trim(),
                    txtDashApiKey.Text.Trim(),
                    chkGarantiasEnabled.Checked,
                    txtGarantiasUrl.Text.Trim(),
                    txtGarantiasApiKey.Text.Trim(),
                    wireCrypt: chkWireCrypt.Checked,
                    spVariant: "Standard",
                    nexusEnabled: chkNexusEnabled.Checked,
                    nexusBaseUrl: txtNexusUrl.Text.Trim(),
                    nexusApiKey: txtNexusApiKey.Text.Trim(),
                    visionEnabled: chkVisionEnabled.Checked,
                    visionBaseUrl: txtVisionUrl.Text.Trim(),
                    visionApiKey: txtVisionApiKey.Text.Trim(),
                    serviceSuffix: txtServiceSuffix.Text.Trim(),
                    vpsEnabled: chkSalesEnabled.Checked);

                // Reinicia o Worker — settings já foram salvas acima, não salva novamente
                _ = EnsureWorkerReadyAsync(saveSettings: false);

                ShowToast("✅  Configurações salvas com sucesso!");

                // Re-bloqueia os campos após gravação bem sucedida
                SetFieldsLockState(true);
                btnUnlock.Text = "🔓  Desbloquear Edição";
                btnUnlock.Enabled = true;
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Erro ao salvar: {ex.Message}", "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // Auto-Setup — instala, configura e inicia o Worker automaticamente
        // ─────────────────────────────────────────────────────────────────────

        /// <summary>
        /// Garante que o Worker esteja instalado, configurado e em execução.
        /// Chamado automaticamente ao abrir o programa e ao salvar configurações.
        /// O usuário não precisa fazer nada.
        /// </summary>
        private async Task EnsureWorkerReadyAsync(bool saveSettings = true)
        {
            string serviceSuffix = "";
            UI(() => { serviceSuffix = txtServiceSuffix.Text.Trim(); });

            if (string.IsNullOrEmpty(serviceSuffix))
            {
                UI(() =>
                {
                    MessageBox.Show("O campo Nome da Empresa está vazio. Por favor, preencha-o e salve as configurações.", "Configuração Obrigatória", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    txtServiceSuffix.Focus();
                });
                return;
            }

            await Task.Run(() =>
            {
                try
                {
                    var installer = new InstallerManager(serviceSuffix);

                    // 1. Extrai o Worker embutido e instala/atualiza o serviço Windows
                    var workerExePath = installer.EnsureWorkerInstalledAndRegistered();
                    if (workerExePath == null)
                    {
                        ShowBalloon("⚠ Configurador",
                            "Não foi possível instalar o Worker. Execute como Administrador.",
                            ToolTipIcon.Warning);
                        return;
                    }

                    // 2. Grava appsettings.json SOMENTE quando explicitamente solicitado.
                    //    saveSettings=false no startup preserva as configurações existentes.
                    if (saveSettings)
                    {
                        string fbDb          = Defaults.FirebirdDb;
                        string vpsUrl        = Defaults.VpsUrl;
                        string vpsKey        = Defaults.VpsApiKey;
                        string idUrl         = Defaults.IdentityUrl;
                        string tenant        = "";
                        string fbUser        = "SYSDBA";
                        string fbPass        = "masterkey";
                        int    catalogInterval = 5;
                        int    orderInterval   = 1;
                        int    maxPoolSize    = 30;
                        int    connectionTimeout = 60;
                        bool   atendenteEnabled = false;
                        string atendenteUrl   = "";
                        string atendenteKey   = "";
                        bool   acEnabled      = false;
                        string acUrl          = "";
                        string acKey          = "";
                        bool   dashEnabled    = false;
                        string dashUrl        = "";
                        string dashKey        = "";
                        bool   nexusEnabled   = false;
                        string nexusUrl       = "";
                        string nexusKey       = "";
                        bool   visionEnabled  = false;
                        string visionUrl      = "";
                        string visionKey      = "";
                        bool   garantiasEnabled = false;
                        string garantiasUrl     = "";
                        string garantiasKey     = "";

                        UI(() =>
                        {
                            fbDb            = txtFirebirdDb.Text.Trim();
                            vpsUrl          = txtVpsUrl.Text.Trim();
                            vpsKey          = txtVpsApiKey.Text.Trim();
                            idUrl           = txtIdentityUrl.Text.Trim();
                            tenant          = txtTenantId.Text.Trim();
                            fbUser          = string.IsNullOrWhiteSpace(txtFirebirdUser.Text) ? "SYSDBA" : txtFirebirdUser.Text.Trim();
                            fbPass          = txtFirebirdPass.Text;
                            catalogInterval = (int)numCatalogSync.Value;
                            orderInterval   = (int)numOrderSync.Value;
                            maxPoolSize     = (int)numMaxPoolSize.Value;
                            connectionTimeout = (int)numConnectionTimeout.Value;
                            atendenteEnabled = chkAtendenteEnabled.Checked;
                            atendenteUrl    = txtAtendenteUrl.Text.Trim();
                            atendenteKey    = txtAtendenteApiKey.Text.Trim();
                            acEnabled       = chkAcEnabled.Checked;
                            acUrl           = txtAcUrl.Text.Trim();
                            acKey           = txtAcApiKey.Text.Trim();
                            dashEnabled     = chkDashEnabled.Checked;
                            dashUrl         = txtDashUrl.Text.Trim();
                            dashKey         = txtDashApiKey.Text.Trim();
                            nexusEnabled    = chkNexusEnabled.Checked;
                            nexusUrl        = txtNexusUrl.Text.Trim();
                            nexusKey        = txtNexusApiKey.Text.Trim();
                            visionEnabled   = chkVisionEnabled.Checked;
                            visionUrl       = txtVisionUrl.Text.Trim();
                            visionKey       = txtVisionApiKey.Text.Trim();
                            garantiasEnabled = chkGarantiasEnabled.Checked;
                            garantiasUrl    = txtGarantiasUrl.Text.Trim();
                            garantiasKey    = txtGarantiasApiKey.Text.Trim();
                        });

                        _settings.UpdateSettings(
                            fbDb, fbUser, fbPass,
                            vpsUrl, vpsKey, idUrl, tenant,
                            catalogInterval, orderInterval,
                            maxPoolSize, connectionTimeout,
                            atendenteEnabled, atendenteUrl, atendenteKey,
                            acEnabled, acUrl, acKey,
                            dashEnabled, dashUrl, dashKey,
                            garantiasEnabled, garantiasUrl, garantiasKey,
                            wireCrypt: chkWireCrypt.Checked,
                            spVariant: "Standard",
                            nexusEnabled: nexusEnabled,
                            nexusBaseUrl: nexusUrl,
                            nexusApiKey: nexusKey,
                            visionEnabled: visionEnabled,
                            visionBaseUrl: visionUrl,
                            visionApiKey: visionKey,
                            serviceSuffix: serviceSuffix);
                    }

                    // 3. Registra URL ACL para o MonitoringServer (HttpListener porta 9001)
                    //    Necessário para Windows Service poder escutar em localhost:9001
                    RegisterUrlAcl("http://localhost:9001/");

                    // 4. Inicia ou reinicia o serviço
                    var serviceName = string.IsNullOrEmpty(serviceSuffix) ? "ColiseuSales Worker" : $"ColiseuSalesWorker_{serviceSuffix}";
                    using var sc = new ServiceController(serviceName);
                    if (sc.Status == ServiceControllerStatus.Running)
                    {
                        sc.Stop();
                        sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(15));
                    }

                    if (sc.Status == ServiceControllerStatus.Stopped)
                    {
                        sc.Start();
                        sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(20));
                        ShowBalloon("✅ Worker iniciado",
                            "Coliseu Sales Worker está sincronizando com a VPS.", ToolTipIcon.Info);
                    }
                }
                catch (InvalidOperationException ex)
                {
                    ShowBalloon("⚠ Permissão necessária",
                        $"Execute como Administrador. ({ex.Message})",
                        ToolTipIcon.Warning);
                }
                catch (Exception ex)
                {
                    ShowBalloon("Erro no auto-setup", ex.Message, ToolTipIcon.Error);
                }
            });
        }

        /// <summary>
        /// Registra URL ACL para o HttpListener do Worker poder escutar em localhost:9001.
        /// Equivale a: netsh http add urlacl url=http://localhost:9001/ user="NT AUTHORITY\SYSTEM"
        /// Ignora se já existir ou se falhar (o serviço tenta mesmo assim).
        /// </summary>
        private static void RegisterUrlAcl(string url)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName               = "netsh",
                    Arguments              = $"http add urlacl url=\"{url}\" user=\"NT AUTHORITY\\SYSTEM\"",
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                };
                using var p = System.Diagnostics.Process.Start(psi);
                p?.WaitForExit(3000);
            }
            catch { /* ignora — o Worker tenta iniciar de qualquer forma */ }
        }

        private void ShowToast(string msg)
        {
            var toast = new Form
            {
                FormBorderStyle = FormBorderStyle.None,
                StartPosition   = FormStartPosition.Manual,
                BackColor       = ColiseuColors.Blue,
                ForeColor       = Color.White,
                Size            = new Size(280, 44),
                TopMost         = true,
                ShowInTaskbar   = false,
            };
            toast.Location = new Point(
                Left + (Width - toast.Width) / 2,
                Bottom - 70);
            toast.Controls.Add(new Label
            {
                Text      = msg,
                Dock      = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter,
                Font      = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.White,
            });
            toast.Show(this);
            var t = new System.Windows.Forms.Timer { Interval = 2000 };
            t.Tick += (_, _) => { toast.Close(); t.Dispose(); };
            t.Start();
        }

        private void BtnBrowse_Click(object? sender, EventArgs e)
        {
            using var dlg = new OpenFileDialog
            {
                Filter = "Banco Firebird (*.fdb)|*.fdb|Todos (*.*)|*.*",
                Title  = "Selecione o arquivo .FDB do Firebird",
            };
            if (dlg.ShowDialog() == DialogResult.OK)
                txtFirebirdDb.Text = dlg.FileName;
        }

        // ─────────────────────────────────────────────────────────────────────
        // UI Helpers
        // ─────────────────────────────────────────────────────────────────────

        private static void AddSection(Control p, string text, int y)
        {
            var lbl = new Label
            {
                Text      = text,
                Location  = new Point(0, y),
                Size      = new Size(700, 20),
                Font      = new Font("Segoe UI", 9f, FontStyle.Bold),
                ForeColor = ColiseuColors.Blue,
            };
            p.Controls.Add(lbl);

            // Linha de separação
            var line = new Panel
            {
                Location  = new Point(0, y + 22),
                Size      = new Size(700, 1),
                BackColor = ColiseuColors.Border,
            };
            p.Controls.Add(line);
        }

        private static void AddFormRow(Control p, string label, out TextBox field,
            int y, bool isPassword = false, bool hasButton = false,
            string? btnText = null, EventHandler? btnAction = null)
        {
            AddFormRow(p, label, out field, y, isPassword, hasButton, btnText, btnAction, out _);
        }

        private static void AddFormRow(Control p, string label, out TextBox field,
            int y, bool isPassword, bool hasButton,
            string? btnText, EventHandler? btnAction, out Button? actionBtn)
        {
            actionBtn = null;
            p.Controls.Add(new Label
            {
                Text      = label,
                Location  = new Point(0, y + 6),
                Size      = new Size(140, 18),
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = ColiseuColors.TextMid,
            });

            var tb = new TextBox
            {
                Location              = new Point(144, y + 2),
                Size                  = new Size(hasButton ? 430 : 540, 28),
                Font                  = new Font("Segoe UI", 9f),
                UseSystemPasswordChar = isPassword,
                BorderStyle           = BorderStyle.FixedSingle,
            };
            p.Controls.Add(tb);
            field = tb;

            if (hasButton && btnText != null && btnAction != null)
            {
                var btn = MakeButton(btnText, 582, y + 1, 100, btnAction);
                btn.Height = 28;
                p.Controls.Add(btn);
                actionBtn = btn;
            }
        }

        private static void AddFormRowCombo(Control p, string label, out ComboBox field,
            int y, string[] items)
        {
            p.Controls.Add(new Label
            {
                Text      = label,
                Location  = new Point(0, y + 6),
                Size      = new Size(140, 18),
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = ColiseuColors.TextMid,
            });

            var cb = new ComboBox
            {
                Location      = new Point(144, y + 2),
                Size          = new Size(540, 28),
                Font          = new Font("Segoe UI", 9f),
                DropDownStyle = ComboBoxStyle.DropDown,
                FlatStyle     = FlatStyle.Flat,
            };
            cb.Items.AddRange(items);
            p.Controls.Add(cb);
            field = cb;
        }

        private static void AddFormRowNumeric(Control p, string label, out NumericUpDown field,
            int y, int min, int max)
        {
            p.Controls.Add(new Label
            {
                Text      = label,
                Location  = new Point(0, y + 6),
                Size      = new Size(180, 18),
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = ColiseuColors.TextMid,
            });

            var nud = new NumericUpDown
            {
                Location  = new Point(184, y + 2),
                Size      = new Size(120, 28),
                Font      = new Font("Segoe UI", 9f),
                Minimum   = min,
                Maximum   = max,
            };
            p.Controls.Add(nud);
            field = nud;
        }

        private static Button MakeButton(string text, int x, int y, int w, EventHandler? handler, bool primary = false)
        {
            var b = new Button
            {
                Text      = text,
                Location  = new Point(x, y),
                Width     = w,
                Height    = 32,
                FlatStyle = FlatStyle.Flat,
                BackColor = primary ? ColiseuColors.Blue : Color.White,
                ForeColor = primary ? Color.White : ColiseuColors.TextDark,
                Font      = new Font("Segoe UI", 9f, primary ? FontStyle.Bold : FontStyle.Regular),
                Cursor    = Cursors.Hand,
            };
            b.FlatAppearance.BorderColor = primary ? ColiseuColors.BlueDark : ColiseuColors.Border;
            b.FlatAppearance.MouseOverBackColor = primary ? ColiseuColors.BlueDark : ColiseuColors.BlueLight;
            if (handler != null) b.Click += handler;
            return b;
        }
    }
}

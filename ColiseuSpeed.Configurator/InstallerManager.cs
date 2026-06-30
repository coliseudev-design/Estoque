using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.ServiceProcess;

namespace ColiseuSpeed.Configurator
{
    public class InstallerManager
    {
        private readonly string _workerServiceName;
        private readonly string _workerDisplayName;
        private readonly string _workerExecutableName = "ColiseuSpeed.Worker.exe";

        public InstallerManager(string suffix = "")
        {
            if (string.IsNullOrEmpty(suffix))
            {
                _workerServiceName = "ColiseuSpeed Worker";
                _workerDisplayName = "ColiseuSpeed Worker";
            }
            else
            {
                _workerServiceName = $"ColiseuSpeedWorker_{suffix}";
                _workerDisplayName = $"Coliseu Speed Worker - {suffix}";
            }
        }

        /// <summary>
        /// Pasta onde o Worker.exe será extraído e mantido.
        /// Usa o diretório REAL do Configurador (via Environment.ProcessPath) e não
        /// AppDomain.CurrentDomain.BaseDirectory, que em single-file publish aponta
        /// para uma pasta temporária de extração do runtime .NET.
        /// </summary>
        public string WorkerInstallDir =>
            Path.GetDirectoryName(Environment.ProcessPath ?? AppDomain.CurrentDomain.BaseDirectory)
            ?? AppDomain.CurrentDomain.BaseDirectory;

        /// <summary>
        /// Garante que o Worker esteja instalado e com o binPath correto.
        /// Retorna o caminho completo do Worker.exe ou null se falhar.
        /// </summary>
        public string? EnsureWorkerInstalledAndRegistered()
        {
            try
            {
                var dir = WorkerInstallDir;
                var baseExe = Path.Combine(dir, "ColiseuSpeed.Worker.exe");

                // 1. Se o serviço já existe e está rodando, paramos temporariamente
                if (IsServiceInstalled())
                {
                    try
                    {
                        using var sc = new ServiceController(_workerServiceName);
                        if (sc.Status != ServiceControllerStatus.Stopped)
                        {
                            sc.Stop();
                            sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(10));
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Aviso ao parar serviço: {ex.Message}");
                    }
                }

                // 2. Extrai o worker embutido SEMPRE, para garantir que atualizações de versão sejam aplicadas
                ExtractEmbeddedWorkerPayload(baseExe);

                if (!File.Exists(baseExe))
                {
                    throw new Exception("Executável do Worker não encontrado na mesma pasta do Configurador, e a extração falhou.");
                }

                // 3. Se o serviço já existe, atualiza o binPath para o caminho atual do Worker
                if (IsServiceInstalled())
                {
                    UpdateServiceBinPath(baseExe);
                }
                else
                {
                    // Instala o serviço pela primeira vez
                    if (!InstallWindowsService(baseExe))
                        return null;
                }

                return baseExe;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Erro na instalação: {ex.Message}");
                return null;
            }
        }



        private void ExtractEmbeddedWorkerPayload(string destinationPath)
        {
            var assembly = Assembly.GetExecutingAssembly();
            // The logic name provided in the .csproj
            using Stream? resourceStream = assembly.GetManifestResourceStream("WorkerPayload.exe");
            if (resourceStream == null)
            {
                // Not found embedded
                return;
            }

            using FileStream fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write);
            resourceStream.CopyTo(fileStream);
        }

        private bool IsServiceInstalled()
        {
            try
            {
                using var sc = new ServiceController(_workerServiceName);
                _ = sc.Status; // lança InvalidOperationException se não existir
                return true;
            }
            catch (InvalidOperationException) { return false; }
        }

        /// <summary>
        /// Atualiza o binPath do serviço existente para apontar para o novo exe.
        /// </summary>
        private void UpdateServiceBinPath(string exePath)
        {
            RunSc($"config \"{_workerServiceName}\" binPath= \"{exePath}\" start= auto displayName= \"{_workerDisplayName}\"");
        }

        private bool InstallWindowsService(string binPath)
        {
            int code = RunSc($"create \"{_workerServiceName}\" binPath= \"{binPath}\" start= auto displayName= \"{_workerDisplayName}\"");
            if (code != 0) return false;

            // Descrição do serviço
            RunSc($"description \"{_workerServiceName}\" \"Serviço de Sincronização do Coliseu Speed ({_workerDisplayName}) (Firebird ↔ VPS)\"");
            return true;
        }

        /// <summary>
        /// Executa sc.exe e retorna o código de saída.
        /// </summary>
        private static int RunSc(string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "sc.exe",
                    Arguments              = arguments,
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                };
                using var p = Process.Start(psi)!;
                p.WaitForExit();
                return p.ExitCode;
            }
            catch { return -1; }
        }
    }
}

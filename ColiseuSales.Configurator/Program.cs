using System;
using System.Windows.Forms;

namespace ColiseuSales.Configurator
{
    internal static class Program
    {
        /// <summary>
        /// Ponto de entrada. Aceita o argumento <c>--minimized</c> para iniciar
        /// na bandeja do sistema sem exibir a janela — usado no boot automático.
        /// </summary>
        [STAThread]
        static void Main(string[] args)
        {
            ApplicationConfiguration.Initialize();
            bool startMinimized = Array.Exists(args, a =>
                a.Equals("--minimized", StringComparison.OrdinalIgnoreCase));
            Application.Run(new MainForm(startMinimized));
        }
    }
}
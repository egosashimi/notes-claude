using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace NotesLauncher
{
    internal static class Program
    {
        [STAThread]
        private static int Main()
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDir, "notes-app.ps1");

            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "Could not find notes-app.ps1 next to Notes.exe.",
                    "Notes",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            var startInfo = new ProcessStartInfo
            {
                FileName = powershellPath,
                Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"",
                WorkingDirectory = appDir,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            Process.Start(startInfo);
            return 0;
        }
    }
}

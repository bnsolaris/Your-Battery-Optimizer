using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Pil Modu")]
[assembly: AssemblyProduct("Pil Modu")]
[assembly: AssemblyVersion("0.3.1.0")]
[assembly: AssemblyFileVersion("0.3.1.0")]

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string folder = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(folder, "Pil-Modu-Uygulamasi.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Pil Modu uygulama dosyası bulunamadı.", script);
            using (Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + script + "\"",
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true
            })) { }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Pil Modu başlatılamadı", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

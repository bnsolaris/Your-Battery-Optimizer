using System;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle(BatteryOptimizer.Product.Name)]
[assembly: AssemblyProduct(BatteryOptimizer.Product.Name)]
[assembly: AssemblyVersion(BatteryOptimizer.Product.Version + ".0")]
[assembly: AssemblyFileVersion(BatteryOptimizer.Product.Version + ".0")]

namespace BatteryOptimizer
{
    internal static class Product
    {
        internal const string Name = "Your Battery Optimizer";
        internal const string Version = "0.5.0";
        internal const string Executable = "YourBatteryOptimizer.exe";
        internal const string WorkerScript = "Apply-PowerProfile.ps1";
        internal const string UninstallScript = "Uninstall.ps1";
        internal const string TranslationsFile = "Translations.json";
        internal const string IconFile = "BatteryOptimizer.ico";

        // Preserve the installed-app identity and saved settings used by previous versions.
        internal const string Registration = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\PilModu.WindowsProfile";
        internal const string WindowEvent = @"Local\PilModu.General.Window";
        internal const string ProfileJournal = @"PilModuProfile\onceki-ayarlar.json";
        internal const string ProfileSettingsFile = "ProfileSettings.json";

        internal static readonly string PowerShell = Path.Combine(Environment.SystemDirectory,
            @"WindowsPowerShell\v1.0\powershell.exe");
    }
}

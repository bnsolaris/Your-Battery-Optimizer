$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\Setup.cs')
$start = $source.IndexOf('internal static class InstallFiles')
$end = $source.IndexOf('#if !UNINSTALL', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Installer class not found.' }
$installer = $source.Substring($start, $end - $start)
$driver = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;
using BatteryOptimizer;

// Only exercise filesystem decisions and shortcut identity matching. No real
// uninstall registry, installed application, or Windows shortcuts are changed.
internal static class Program {
    internal static Stream Resource(string name) { throw new NotSupportedException(); }
}

public static class PilModuReinstallTest {
    private static void Check(bool condition, string message) {
        if (!condition) throw new Exception(message);
    }
    private static void Reject(Action action, string message) {
        bool rejected = false;
        try { action(); } catch (InvalidOperationException) { rejected = true; }
        Check(rejected, message);
    }

    public static void Run(string root, string catalog) {
        string[] locales = { "en-GB", "tr-TR", "ru-RU", "es-MX", "de-DE" };
        string[] expected = { "Install", "Kur", "\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C", "Instalar", "Install" };
        for (int i = 0; i < locales.Length; i++) {
            UiText.LoadJson(catalog, locales[i]);
            Check(UiText.Get("Install") == expected[i], "Wrong default language: " + locales[i]);
            Check(UiText.Get("Step", Product.Version, 2).Contains(Product.Version), "Version was not inserted.");
            Check(UiText.Get("TermsBody").Contains("https://github.com/bnsolaris"), "The setup attribution is missing.");
        }
        UiText.Select("tr");
        Check(UiText.Get("Install") == "Kur", "Manual selection did not replace the detected language.");
        UiText.Select("en");

        const string id = "1c1818cc-e2e2-4458-a806-224272baaa5d";
        string missing = Path.Combine(root, "Deleted");
        Check(InstallFiles.ValidateOrphanedRegistration(missing, id) == missing,
            "A deleted installation folder was not recoverable.");
        Check(InstallFiles.ValidateFolder(missing, missing, id) == missing,
            "A deleted installation folder was not installable.");

        string folder = Path.Combine(root, "Existing");
        Directory.CreateDirectory(folder);
        Check(InstallFiles.ValidateOrphanedRegistration(folder, id) == folder,
            "An empty installation folder was not recoverable.");
        string marker = Path.Combine(folder, InstallFiles.Marker);
        File.WriteAllText(marker, id);
        File.SetAttributes(marker, FileAttributes.Hidden);
        Check(InstallFiles.ValidateOrphanedRegistration(folder, id) == folder &&
              InstallFiles.ValidateFolder(folder, folder, id) == folder,
            "A matching hidden marker blocked reinstall.");
        Reject(() => InstallFiles.ValidateOrphanedRegistration(folder, "different-id"),
            "A mismatching installation marker was accepted.");
        Reject(() => InstallFiles.ValidateFolder(folder, missing, id),
            "Another folder's marker was accepted.");
        Check(File.ReadAllText(marker) == id, "The old installation marker changed during validation.");

        foreach (string name in InstallFiles.Payload.Concat(InstallFiles.LegacyPayload).Distinct()) {
            string payload = Path.Combine(folder, name);
            File.WriteAllText(payload, "existing-file");
            Reject(() => InstallFiles.ValidateOrphanedRegistration(folder, id),
                "An installation with remaining app files was treated as deleted: " + name);
            Check(File.ReadAllText(payload) == "existing-file", "An existing app file was changed.");
            File.Delete(payload);
        }

        string foreign = Path.Combine(folder, "keep.txt");
        File.WriteAllText(foreign, "leave this file alone");
        Check(InstallFiles.ValidateOrphanedRegistration(folder, id) == folder,
            "Unrelated files prevented recognizing the missing application.");
        Reject(() => InstallFiles.ValidateFolder(folder, folder, id),
            "A nonempty folder with unrelated files was accepted.");
        Check(InstallFiles.ValidateFolder(missing, folder, id) == missing,
            "Recovery to a different empty location was blocked.");
        Check(File.ReadAllText(foreign) == "leave this file alone", "A foreign file was changed.");

        string target = Path.Combine(folder, Product.Executable);
        Check(InstallFiles.IsOwnedShortcutTarget(target, "", folder), "An owned shortcut was rejected.");
        Check(InstallFiles.DisplayIcon(folder) == "\"" + target + "\",0", "The Windows Apps icon does not use the app executable.");
        Check(InstallFiles.IsOwnedShortcutTarget(Path.Combine(folder, "PilModu.exe"), "", folder),
            "The earlier app executable is no longer recognized.");
        Check(!InstallFiles.IsOwnedShortcutTarget(Path.Combine(missing, Product.Executable), "", folder),
            "Another installation's shortcut was accepted.");
        Check(!InstallFiles.IsOwnedShortcutTarget(target, "--different-program", folder),
            "A shortcut with unexpected arguments was accepted.");
        string legacy = "-WindowStyle Hidden -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File \"" +
            Path.Combine(folder, "Pil-Modu-Uygulamasi.ps1") + "\"";
        Check(InstallFiles.IsOwnedShortcutTarget(InstallFiles.PowerShell, legacy, folder),
            "An owned legacy shortcut was rejected.");
        Check(!InstallFiles.IsOwnedShortcutTarget(InstallFiles.PowerShell, legacy + " extra", folder),
            "A modified legacy shortcut was accepted.");

        File.Delete(foreign);
        File.SetAttributes(marker, FileAttributes.Normal);
        File.Delete(marker);
        Directory.Delete(folder);
    }
}
'@
$shared = foreach ($name in 'Product.cs', 'Localization.cs') {
    $code = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root "src\$name")
    $code.Substring($code.IndexOf('namespace BatteryOptimizer'))
}
Add-Type -TypeDefinition ($driver + [Environment]::NewLine + $installer + ($shared -join [Environment]::NewLine)) `
    -ReferencedAssemblies System.Core, Microsoft.CSharp, System.Web.Extensions
$catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\Translations.json')
$fixture = Join-Path $root ('obj\test-reinstall-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
    [PilModuReinstallTest]::Run($fixture, $catalog)
    Write-Output 'PASS: language detection, manual selection, display icon, deleted folders, previous installations and shortcut ownership.'
}
finally {
    $folder = Join-Path $fixture 'Existing'
    foreach ($name in @('YourBatteryOptimizer.exe', 'BatteryOptimizer.Native.dll', 'Apply-PowerProfile.ps1', 'Uninstall.ps1',
        'Localization.ps1', 'Translations.json', 'BatteryOptimizer.ico',
        'PilModu.exe', 'PilModu.Native.dll', 'PilModu.Visuals.dll', 'Pil-Modu-Uygulamasi.ps1',
        'Pil-Modu.ps1', 'Kaldir.ps1', 'Pil-Modu.ico', 'README.txt', 'Uninstall.exe', '.pilmodu-install', 'keep.txt')) {
        $file = Join-Path $folder $name
        if ([IO.File]::Exists($file)) {
            [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($file)
        }
    }
    if ([IO.Directory]::Exists($folder)) { [IO.Directory]::Delete($folder) }
    [IO.Directory]::Delete($fixture)
}

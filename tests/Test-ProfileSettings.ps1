$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('obj\test-settings-' + [guid]::NewGuid().ToString('N'))
$harness = Join-Path $fixture 'VerifySettings.cs'
$file = Join-Path $fixture 'ProfileSettings.json'
[void][IO.Directory]::CreateDirectory($fixture)
$driver = @'
using System;
using System.IO;
using BatteryOptimizer;

public static class VerifySettings
{
    public static void Run(string path)
    {
        var settings = ProfileSettings.Load(path);
        if (!settings.HasEnabledSettings || settings.DisabledSettings() != "" || settings.RefreshRate != 60 ||
            settings.BrightnessPercent != 30 || settings.VolumePercent != 20 || settings.SaverPercent != 100 ||
            settings.PowerMode != "Efficiency")
            throw new Exception("Incorrect defaults.");

        settings.Display = settings.Audio = settings.Wallpaper = false;
        settings.RefreshRate = 90;
        settings.BrightnessPercent = 46;
        settings.VolumePercent = 0;
        settings.SaverPercent = 55;
        settings.PowerMode = "Balanced";
        settings.Save(path);
        var saved = ProfileSettings.Load(path);
        if (!saved.HasEnabledSettings || saved.DisabledSettings() != "Display,Audio,Wallpaper" ||
            saved.RefreshRate != 90 || saved.BrightnessPercent != 46 || saved.VolumePercent != 0 ||
            saved.SaverPercent != 55 || saved.PowerMode != "Balanced")
            throw new Exception("Settings did not survive a reload.");

        saved.Brightness = saved.Power = saved.Saver = false;
        saved.Save(path);
        var disabled = ProfileSettings.Load(path);
        if (disabled.HasEnabledSettings || disabled.DisabledSettings() != "Display,Brightness,Audio,Power,Saver,Wallpaper")
            throw new Exception("The all-disabled profile was not saved.");

        disabled.BrightnessPercent = 101;
        bool invalid = false;
        try { disabled.Save(path); }
        catch (InvalidDataException) { invalid = true; }
        if (!invalid || ProfileSettings.Load(path).BrightnessPercent != 46)
            throw new Exception("Invalid settings overwrote the last valid profile.");
    }
}
'@
try {
    [IO.File]::WriteAllText($harness, $driver, [Text.Encoding]::UTF8)
    Add-Type -Path @((Join-Path $root 'src\ProfileSettings.cs'), $harness) -ReferencedAssemblies System.Core, System.Web.Extensions
    [VerifySettings]::Run($file)
    Write-Output 'PASS: defaults, per-setting switches, target persistence and invalid values.'
}
finally {
    if ([IO.File]::Exists($harness)) { [IO.File]::Delete($harness) }
    if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
    [IO.Directory]::Delete($fixture)
}

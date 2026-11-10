$ErrorActionPreference = 'Stop'
$profilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Pil-Modu.ps1'
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

# Exercise the real profile/journal code with a fake desktop; never change
# the test runner's wallpaper, display, audio or power settings.
foreach ($definition in $ast.EndBlock.Statements) {
    if ($definition -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}
Add-Type -TypeDefinition @'
public static class PilModuWallpaperTestNative {
    public sealed class State {
        public uint Color { get; set; }
        public bool Enabled { get; set; }
    }
    public static uint Color;
    public static bool Enabled;
    public static bool FailNextWrite;
    public static int Writes;
    public static System.Action BeforeWrite;
    public static State GetState() {
        return new State { Color = Color, Enabled = Enabled };
    }
    public static void SetBackground(uint color, bool enabled) {
        BeforeWrite();
        Writes++;
        if (FailNextWrite) {
            FailNextWrite = false;
            throw new System.InvalidOperationException("Simulated desktop failure.");
        }
        Color = color;
        Enabled = enabled;
    }
}
'@
$stateDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('obj\test-wallpaper-' + [guid]::NewGuid().ToString('N'))
$statePath = Join-Path $stateDirectory 'onceki-ayarlar.json'
$steps = [ordered]@{}
$journal = @{}
foreach ($id in 'Display', 'Brightness', 'Audio', 'Power', 'Saver') {
    New-Setting $id $id { @{ Value = 0; Target = 0 } } { throw 'An unchanged setting was written.' }
}
$wallpaper = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'New-Setting' -and
        $node.CommandElements[1].Value -eq 'Wallpaper'
}, $true)
if (-not $wallpaper) { throw 'Wallpaper setting was not registered.' }
. ([scriptblock]::Create($wallpaper.Extent.Text.Replace('[PilModu.NativeWallpaper]', '[PilModuWallpaperTestNative]')))
[PilModuWallpaperTestNative]::BeforeWrite = {
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'Desktop changed before saving its restore point.' }
    $saved = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($saved.Wallpaper.Value.Color -ne $expectedColor -or $saved.Wallpaper.Value.Enabled -ne $expectedEnabled) {
        throw 'The original desktop restore point was overwritten.'
    }
}

function Invoke-TestProfile([string]$Profile) {
    $Mode = $Profile
    $journal = @{} # Simulate a fresh worker process on every mode change.
    Invoke-Profile
}

function Assert-Desktop([uint32]$Color, [bool]$Enabled) {
    if ([PilModuWallpaperTestNative]::Color -ne $Color -or [PilModuWallpaperTestNative]::Enabled -ne $Enabled) {
        throw 'The expected desktop state was not applied.'
    }
}

try {
    foreach ($initialEnabled in @($true, $false)) {
        $expectedColor = [uint32]0x123456
        $expectedEnabled = $initialEnabled
        [PilModuWallpaperTestNative]::Color = $expectedColor
        [PilModuWallpaperTestNative]::Enabled = $expectedEnabled
        Invoke-TestProfile 'Disari'
        Assert-Desktop 0 $false
        Invoke-TestProfile 'Disari'
        Assert-Desktop 0 $false
        Invoke-TestProfile 'Normal'
        Assert-Desktop $expectedColor $expectedEnabled
        if (Test-Path -LiteralPath $statePath) { throw 'A completed restore left a pending journal.' }
    }

    # Already-black desktops and read-only status need no restore entry or writes.
    [PilModuWallpaperTestNative]::Color = 0
    [PilModuWallpaperTestNative]::Enabled = $false
    $writes = [PilModuWallpaperTestNative]::Writes
    Invoke-TestProfile 'Disari'
    Invoke-TestProfile 'Durum'
    Invoke-TestProfile 'Normal'
    if ((Test-Path -LiteralPath $statePath) -or [PilModuWallpaperTestNative]::Writes -ne $writes) {
        throw 'An already-black desktop was changed unnecessarily.'
    }

    $expectedColor = [uint32]0xABCDEF
    $expectedEnabled = $true
    [PilModuWallpaperTestNative]::Color = $expectedColor
    [PilModuWallpaperTestNative]::Enabled = $expectedEnabled
    Invoke-TestProfile 'Disari'
    [PilModuWallpaperTestNative]::FailNextWrite = $true
    $failedRestore = $false
    try { Invoke-TestProfile 'Normal' } catch { $failedRestore = $true }
    if (-not $failedRestore -or -not (Test-Path -LiteralPath $statePath)) {
        throw 'A failed restore lost the retry journal.'
    }
    Invoke-TestProfile 'Normal'
    Assert-Desktop $expectedColor $expectedEnabled
    if (Test-Path -LiteralPath $statePath) { throw 'Retry did not complete the restore.' }

    # A failed apply must also retain the original state for Normal mode.
    [PilModuWallpaperTestNative]::FailNextWrite = $true
    Invoke-TestProfile 'Disari'
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'A failed apply lost the restore point.' }
    Invoke-TestProfile 'Normal'
    Assert-Desktop $expectedColor $expectedEnabled

    # Old journals without wallpaper remain compatible and do not touch it.
    [IO.File]::WriteAllText($statePath, '{"Display":{"Value":0,"Target":0}}')
    $steps.Display.Write = { param($entry, $value) }
    $writes = [PilModuWallpaperTestNative]::Writes
    Invoke-TestProfile 'Normal'
    if ((Test-Path -LiteralPath $statePath) -or [PilModuWallpaperTestNative]::Writes -ne $writes) {
        throw 'An older journal changed the wallpaper.'
    }
    Write-Output 'PASS: wallpaper persistence, repeated activation, solid colors, no-op, failures, retries and old journals.'
}
finally {
    [PilModuWallpaperTestNative]::BeforeWrite = $null
    foreach ($file in @($statePath, "$statePath.new")) {
        if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
    }
    if ([IO.Directory]::Exists($stateDirectory)) { [IO.Directory]::Delete($stateDirectory) }
}

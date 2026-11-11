$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Localization.ps1')
$translations = Import-Translations (Join-Path $root 'src') 'en'
$profileAst = $null
foreach ($name in @('src\Apply-PowerProfile.ps1', 'Repair-Uninstall.ps1')) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name), [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($definition in $ast.EndBlock.Statements) {
        if ($definition -is [Management.Automation.Language.FunctionDefinitionAst]) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
    if ($name -eq 'src\Apply-PowerProfile.ps1') { $profileAst = $ast }
}

# Mock only the Windows provider. Test the real brightness step and journal
# without reading or changing the runner's screen or installed application.
function Get-CimInstance($Namespace, $ClassName) {
    if ($Namespace -ne 'root/wmi') { throw 'Unexpected namespace.' }
    switch ($ClassName) {
        'WmiMonitorBrightness' {
            [pscustomobject]@{ Active = $true; InstanceName = $script:panelId;
                CurrentBrightness = $script:brightness; Level = @(10, 20, 30, 40, 50, 60, 70) }
        }
        'WmiMonitorBrightnessMethods' { [pscustomobject]@{ Active = $true; InstanceName = $script:panelId } }
        default { throw 'Unexpected provider.' }
    }
}
function Invoke-CimMethod($InputObject, $MethodName, $Arguments) {
    if ($MethodName -ne 'WmiSetBrightness' -or $InputObject.InstanceName -ne $script:panelId) { throw 'Unexpected method.' }
    $script:writes++
    if ($script:applyWrites) { $script:brightness = [int]$Arguments.Brightness }
    switch ($script:returnMode) {
        'Null' { return $null }
        'Empty' { return [pscustomobject]@{} }
        'Zero' { return [pscustomobject]@{ ReturnValue = 0 } }
        'NonZero' { return [pscustomobject]@{ ReturnValue = 5 } }
        'Throw' { throw 'Provider exception.' }
    }
}
function Start-Sleep($Milliseconds) { }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert $failed $Message
}

$stateDirectory = Join-Path $root ('obj\test-brightness-' + [guid]::NewGuid().ToString('N'))
$statePath = Join-Path $stateDirectory 'onceki-ayarlar.json'
$backupRoot = Join-Path $stateDirectory 'backups'
[void][IO.Directory]::CreateDirectory($stateDirectory)
$steps = [ordered]@{}
$AwayBrightness = 30
foreach ($id in 'Display', 'Audio', 'Power', 'Saver', 'Wallpaper') {
    New-Setting $id $id { @{ Value = 0; Target = 0 } } { throw 'An unrelated setting was changed.' }
}
$registration = $profileAst.Find({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'New-Setting' -and $node.CommandElements[1].Value -eq 'Brightness'
}, $true)
if (-not $registration) { throw 'Brightness step not found.' }
. ([scriptblock]::Create($registration.Extent.Text))

function Reset-Case([int]$Current = 30) {
    $script:panelId = 'test-panel'
    $script:brightness = $Current
    $script:writes = 0
    $script:returnMode = 'Null'
    $script:applyWrites = $true
    $saved = @{ Brightness = @{ Id = 'test-panel'; Value = 40; Target = 30 } }
    [IO.File]::WriteAllText($statePath, ($saved | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
}
function Run-Normal {
    $Mode = 'Normal'
    $journal = @{}
    Invoke-Profile
}
function Run-Mode([string]$RequestedMode) {
    $Mode = $RequestedMode
    $journal = @{}
    Invoke-Profile
}

try {
    $expectedLabels = @{
        'en-GB' = 'Brightness'
        'tr-TR' = 'Parlaklık'
        'ru-RU' = 'Яркость'
        'es-MX' = 'Brillo'
        'de-DE' = 'Brightness'
    }
    foreach ($locale in $expectedLabels.Keys) {
        $translations = Import-Translations (Join-Path $root 'src') $locale
        Assert ((Get-Text 'Brightness') -ceq $expectedLabels[$locale]) "Unexpected language for $locale"
        Assert ((Get-Text 'BrightnessValue' @(40)).Contains('40')) "Missing formatted value for $locale"
    }
    $translations = Import-Translations (Join-Path $root 'src') 'en'

    Reset-Case 70
    [IO.File]::Delete($statePath)
    $script:audioReads = 0
    $steps.Audio.Read = {
        $script:audioReads++
        @{ Value = 0; Target = 0 }
    }
    $DisabledSettings = @('Display', 'Audio', 'Power', 'Saver', 'Wallpaper')
    $AwayBrightness = 27
    Run-Mode 'Away'
    Assert ($brightness -eq 20 -and $audioReads -eq 0) 'The brightness limit or disabled action was ignored.'
    $AwayBrightness = 40
    Run-Mode 'Away'
    $original = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    Assert ($brightness -eq 40 -and $original.Brightness.Value -eq 70) 'The new target did not preserve the original value.'
    $DisabledSettings = @($steps.Keys)
    $AwayBrightness = 10
    Run-Mode 'Away'
    Assert ($brightness -eq 40 -and $writes -eq 2 -and (Test-Path -LiteralPath $statePath)) 'Disabling an action changed its value or discarded its restore record.'
    $report = (Run-Mode 'Status' 6>&1 | Out-String)
    Assert ($report.Contains('Brightness: 40%') -and $writes -eq 2) 'Overview did not read the actual brightness without writing.'
    Run-Normal
    Assert ($brightness -eq 70 -and $writes -eq 3 -and -not (Test-Path -LiteralPath $statePath)) 'Normal mode did not restore an action that was disabled later.'
    $DisabledSettings = @()
    $AwayBrightness = 30
    $steps.Audio.Read = { @{ Value = 0; Target = 0 } }

    Reset-Case 40
    Run-Normal
    Assert ($writes -eq 0 -and -not (Test-Path -LiteralPath $statePath)) 'Already-restored brightness was not accepted.'

    foreach ($mode in 'Null', 'Empty', 'Zero', 'NonZero', 'Throw') {
        Reset-Case
        $script:returnMode = $mode
        Run-Normal
        Assert ($brightness -eq 40 -and $writes -eq 1 -and -not (Test-Path -LiteralPath $statePath)) "Actual restore failed with response: $mode"
    }
    foreach ($mode in 'Null', 'Zero', 'NonZero', 'Throw') {
        Reset-Case
        $script:returnMode = $mode
        $script:applyWrites = $false
        Reject { Run-Normal } "A failed restore was accepted with response: $mode"
        Assert (Test-Path -LiteralPath $statePath) 'A failed restore lost its journal.'
    }
    Reset-Case
    $script:panelId = 'another-panel'
    Reject { Run-Normal } 'The wrong panel was accepted.'
    Assert ($writes -eq 0 -and (Test-Path -LiteralPath $statePath)) 'The wrong panel was written or its journal lost.'

    Reset-Case
    Reject { Repair-BrightnessJournal $statePath $backupRoot } 'Recovery accepted an unrestored brightness.'
    Assert (Test-Path -LiteralPath $statePath) 'Recovery discarded an unrestored value.'
    Assert (-not (Test-Path -LiteralPath $backupRoot)) 'Recovery wrote files before verifying brightness.'

    Reset-Case 40
    $original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
    $result = Repair-BrightnessJournal $statePath $backupRoot
    Assert (-not (Test-Path -LiteralPath $statePath)) 'Verified recovery did not unblock removal.'
    Assert ($original -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath))) 'Recovery backup differs from the original journal.'

    Reset-Case 40
    $saved = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $saved | Add-Member NoteProperty Audio ([pscustomobject]@{ Id = 'saved-audio'; Value = 0.75; Target = 0.2 })
    [IO.File]::WriteAllText($statePath, ($saved | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
    $result = Repair-BrightnessJournal $statePath $backupRoot
    $remaining = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    Assert ($result.Remaining.Count -eq 1 -and $result.Remaining[0] -eq 'Audio' -and
        $remaining.Audio.Value -eq 0.75 -and -not $remaining.Brightness) 'Recovery discarded another pending setting.'

    Reset-Case 0
    [IO.File]::WriteAllText($statePath, '{"Brightness":{"Id":"test-panel","Value":null,"Target":30}}')
    Reject { Repair-BrightnessJournal $statePath $backupRoot } 'Recovery coerced an invalid value to zero.'
    Assert (Test-Path -LiteralPath $statePath) 'An invalid journal was deleted.'
    Write-Output 'PASS: readback, already-restored values, missing status, provider failures, panel identity and backed-up uninstall recovery.'
}
finally {
    foreach ($file in @($statePath, "$statePath.new")) {
        if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
    }
    if ([IO.Directory]::Exists($backupRoot)) {
        foreach ($file in [IO.Directory]::GetFiles($backupRoot)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($backupRoot)
    }
    [IO.Directory]::Delete($stateDirectory)
}

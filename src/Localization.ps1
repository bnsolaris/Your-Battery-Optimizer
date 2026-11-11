function Import-Translations([string]$Folder, [string]$Language) {
    if (-not $Language) { $Language = [Globalization.CultureInfo]::CurrentUICulture.Name }
    $code = $Language.Split('-')[0].ToLowerInvariant()
    if ($code -notin @('en', 'tr', 'ru', 'es')) { $code = 'en' }
    $catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Folder 'Translations.json') | ConvertFrom-Json
    [pscustomobject]@{ Language = $code; Catalog = $catalog }
}

function Get-Text([string]$Key, [object[]]$Values = @()) {
    $entry = $translations.Catalog.PSObject.Properties[$Key]
    if (-not $entry) { throw "Missing translation key: $Key" }
    $template = $entry.Value.($translations.Language)
    if (-not $template) { $template = $entry.Value.en }
    if ($Values.Count -eq 0) { return $template }
    return [string]::Format([Globalization.CultureInfo]::CurrentCulture, $template, $Values)
}

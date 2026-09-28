param(
    [switch]$Write,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

if (-not (Test-Path -LiteralPath $env:PSSCRIPTANALYZER_MODULE)) {
    Write-Error "PSScriptAnalyzer is required but is unavailable in this environment."
    exit 2
}

Import-Module -Name $env:PSSCRIPTANALYZER_MODULE -Force
$formatDrift = @()

foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    $original = Get-Content -LiteralPath $path -Raw
    $formatted = Invoke-Formatter -ScriptDefinition $original -Settings CodeFormatting

    if ($formatted -ne $original) {
        if ($Write) {
            [System.IO.File]::WriteAllText($path, $formatted, [System.Text.UTF8Encoding]::new($false))
            continue
        }

        $formatDrift += [PSCustomObject]@{
            ScriptName = Split-Path -Leaf $path
            Path       = $path
        }
    }
}

if ($formatDrift.Count -gt 0) {
    $formatDrift | Format-Table -AutoSize
    Write-Host "PowerShell formatter found $($formatDrift.Count) file(s) with formatting drift" -ForegroundColor Red
    exit 1
}

if ($Write) {
    exit 0
}

Write-Host "PowerShell formatter: No formatting drift found" -ForegroundColor Green

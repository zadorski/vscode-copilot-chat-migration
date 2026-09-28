param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

if (-not (Test-Path -LiteralPath $env:PSSCRIPTANALYZER_MODULE)) {
    Write-Error "PSScriptAnalyzer is required but is unavailable in this environment."
    exit 2
}

Import-Module -Name $env:PSSCRIPTANALYZER_MODULE -Force
$allResults = @()

foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    $results = Invoke-ScriptAnalyzer -Path $path -Settings PSGallery -ExcludeRule PSUseSingularNouns
    if ($results) {
        $allResults += $results
    }
}

if ($allResults.Count -gt 0) {
    $allResults | Format-Table -AutoSize
    Write-Host "PSScriptAnalyzer found $($allResults.Count) issue(s)" -ForegroundColor Red
    exit 1
}

Write-Host "PSScriptAnalyzer: No issues found" -ForegroundColor Green

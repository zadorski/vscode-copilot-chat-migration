#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MappingPath,
    [switch]$Open,
    [switch]$SkipPrompt,
    [int]$DelayMilliseconds = 750
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CopilotChatsMigration.psm1') -Force

if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) {
    throw "Migration map not found at: $MappingPath"
}

$map = Get-Content -LiteralPath $MappingPath -Raw | ConvertFrom-Json
$entries = @(
    $map.Mappings |
        Where-Object { $_.TargetUri } |
        Group-Object TargetUri |
        ForEach-Object { $_.Group | Select-Object -First 1 }
)

if ($entries.Count -eq 0) {
    throw 'The migration map has no target URIs.'
}

$targets = @(
    foreach ($entry in $entries) {
        $info = Get-CcmWorkspaceInfo -RawUri $entry.TargetUri
        [PSCustomObject]@{
            TargetUri = $entry.TargetUri
            Distro = $info.RemoteName
            Type = $info.Type
            TargetPath = $info.Path
            Status = $entry.Status
        }
    }
)

$targets | Sort-Object Distro, TargetPath | Format-Table Distro, TargetPath, Status -AutoSize

if (-not $Open) {
    Write-Host 'No workspaces opened. Re-run with -Open after reviewing the list.' -ForegroundColor Yellow
    return
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    throw 'wsl.exe was not found. Run this script from Windows PowerShell on the Windows host.'
}

if (-not $SkipPrompt) {
    $confirmed = Read-Host "Open $($targets.Count) target workspace(s) through code-wsl? (Y/N)"
    if ($confirmed -notmatch '^[Yy]$') {
        Write-Host 'Target preparation cancelled.' -ForegroundColor Yellow
        return
    }
}

function ConvertTo-CcmBashSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)
    $escaped = $Value.Replace("'", "'\''")
    return "'" + $escaped + "'"
}

foreach ($target in $targets) {
    if ($target.Type -ne 'WSL' -or [string]::IsNullOrWhiteSpace($target.Distro)) {
        Write-Warning "Skipping unsupported target URI: $($target.TargetUri)"
        continue
    }

    $remoteCommand = "WSLEDIT_CONTEXT=code-wsl code-wsl --new-window -- $(ConvertTo-CcmBashSingleQuoted -Value $target.TargetPath)"
    Write-Host "Opening $($target.Distro): $($target.TargetPath)" -ForegroundColor Cyan
    & $wslCommand.Source --distribution $target.Distro -- bash -lc $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "code-wsl failed for $($target.TargetUri) with exit code $LASTEXITCODE"
    }
    if ($DelayMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
}

Write-Host 'Target workspace preparation complete. Close VS Code before importing state.' -ForegroundColor Green
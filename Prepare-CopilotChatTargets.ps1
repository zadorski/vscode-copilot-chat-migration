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
        Sort-Object SourcePath, SourceWorkspaceKind, SourceId
)

if ($entries.Count -eq 0) {
    throw 'The migration map has no target URIs.'
}

$mapCollisions = @(
    $entries |
        Group-Object TargetUri |
        Where-Object Count -GT 1
)
if ($mapCollisions.Count -gt 0) {
    $collisionUris = $mapCollisions | ForEach-Object Name
    throw "Refusing to prepare duplicate target URIs: $($collisionUris -join ', '). Regenerate the map after resolving collisions."
}
$unresolvedEntries = @($entries | Where-Object { [string]$_.Status -like 'Target collision:*' })
if ($unresolvedEntries.Count -gt 0) {
    throw 'Refusing to prepare a map containing unresolved target collision statuses.'
}

$targetWorkspaceStoragePath = if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    $null
}
else {
    Join-Path $env:APPDATA 'Code\User\workspaceStorage'
}
$targetRecords = if ($targetWorkspaceStoragePath -and (Test-Path -LiteralPath $targetWorkspaceStoragePath -PathType Container)) {
    @(Get-CcmWorkspaceRecords -WorkspaceStoragePath $targetWorkspaceStoragePath)
}
else {
    @()
}
$existingTargetGroups = @($targetRecords | Group-Object RawUri | Where-Object Count -GT 1)
if ($existingTargetGroups.Count -gt 0) {
    $duplicateUris = $existingTargetGroups | ForEach-Object Name
    throw "Target workspaceStorage contains duplicate records for: $($duplicateUris -join ', '). Resolve duplicates before preparation."
}
$existingTargetUris = @{}
foreach ($record in $targetRecords) {
    $existingTargetUris[$record.RawUri] = $record
}

$targets = @(
    foreach ($entry in $entries) {
        $info = Get-CcmWorkspaceInfo -RawUri $entry.TargetUri
        $existing = $existingTargetUris[$entry.TargetUri]
        [PSCustomObject]@{
            TargetUri  = $entry.TargetUri
            Distro     = $info.RemoteName
            Type       = $info.Type
            TargetPath = $info.Path
            Status     = if ($existing) { 'Already exists' } else { 'Missing' }
            ExistingId = if ($existing) { $existing.ID } else { $null }
        }
    }
)

$targets | Sort-Object Distro, TargetPath | Format-Table Distro, TargetPath, Status -AutoSize
$pendingTargets = @($targets | Where-Object Status -EQ 'Missing')
$unsupportedTargets = @(
    $pendingTargets |
        Where-Object { $_.Type -ne 'WSL' -or [string]::IsNullOrWhiteSpace($_.Distro) }
)
if ($unsupportedTargets.Count -gt 0) {
    $unsupportedUris = $unsupportedTargets | ForEach-Object TargetUri
    throw "Refusing to open unsupported target URIs: $($unsupportedUris -join ', ')."
}

if ($pendingTargets.Count -eq 0) {
    Write-Host 'All target workspace records already exist. No target windows need to be opened.' -ForegroundColor Green
    return
}

if (-not $Open) {
    Write-Host "$($pendingTargets.Count) target workspace record(s) are missing. Re-run with -Open after reviewing the list." -ForegroundColor Yellow
    return
}

if ($IsWindows -ne $true) {
    throw 'Opening targets requires Windows PowerShell on the Windows host. Run this script from Windows Terminal PowerShell 7.5+; use WSL only for dry-run inspection.'
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    throw 'wsl.exe was not found. Run this script from Windows PowerShell on the Windows host.'
}

if (-not $SkipPrompt) {
    $confirmed = Read-Host "Open $($pendingTargets.Count) missing target workspace(s) through code-wsl? (Y/N)"
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

foreach ($target in $pendingTargets) {
    $quotedTargetPath = ConvertTo-CcmBashSingleQuoted -Value $target.TargetPath
    $remoteCommand = @(
        'set -e'
        'unset VSCODE_IPC_HOOK_CLI WSLEDIT_CODE_REMOTE_CLI VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_MAIN'
        "command -v code-wsl >/dev/null 2>&1 || { printf '%s\n' 'code-wsl is unavailable in the target distro' >&2; exit 127; }"
        "test -e $quotedTargetPath || { printf '%s\n' 'target path does not exist in the target distro' >&2; exit 2; }"
        "WSLEDIT_CONTEXT=code-wsl code-wsl --new-window -- $quotedTargetPath"
    ) -join '; '
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
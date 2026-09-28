#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MappingPath,
    [string]$WorkspaceStoragePath,
    [switch]$Open,
    [switch]$SkipPrompt,
    [string]$OpenCommand = 'code',
    [string[]]$OpenArgument = @('--new-window'),
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

$targetWorkspaceStoragePath = if ($WorkspaceStoragePath) {
    $WorkspaceStoragePath
}
else {
    Get-CcmDefaultWorkspaceStoragePath
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

$targets | Sort-Object Type, Distro, TargetPath | Format-Table Type, Distro, TargetPath, Status -AutoSize
$pendingTargets = @($targets | Where-Object Status -EQ 'Missing')

if ($pendingTargets.Count -eq 0) {
    Write-Host 'All target workspace records already exist. No target windows need to be opened.' -ForegroundColor Green
    return
}

if (-not $Open) {
    Write-Host "$($pendingTargets.Count) target workspace record(s) are missing. Re-run with -Open after reviewing the list." -ForegroundColor Yellow
    return
}

if ([string]::IsNullOrWhiteSpace($OpenCommand)) {
    throw 'An opener command is required with -Open. Pass a VS Code-compatible command that accepts a workspace URI.'
}

$openCommandInfo = if (Test-Path -LiteralPath $OpenCommand -PathType Leaf) {
    Get-Item -LiteralPath $OpenCommand
}
else {
    Get-Command $OpenCommand -CommandType Application, ExternalScript -ErrorAction SilentlyContinue
}
if (-not $openCommandInfo) {
    throw "Opener command not found: $OpenCommand. Pass -OpenCommand with a VS Code-compatible executable or script."
}
$openCommandPath = if ($openCommandInfo -is [System.IO.FileInfo]) {
    $openCommandInfo.FullName
}
else {
    $openCommandInfo.Source
}

if (-not $SkipPrompt) {
    $confirmed = Read-Host "Open $($pendingTargets.Count) missing target workspace(s) with $OpenCommand? (Y/N)"
    if ($confirmed -notmatch '^[Yy]$') {
        Write-Host 'Target preparation cancelled.' -ForegroundColor Yellow
        return
    }
}

foreach ($target in $pendingTargets) {
    $arguments = @($OpenArgument) + $target.TargetUri
    Write-Host "Opening $($target.Type) $($target.Distro): $($target.TargetPath)" -ForegroundColor Cyan
    & $openCommandPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Opener command failed for $($target.TargetUri) with exit code $LASTEXITCODE"
    }
    if ($DelayMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
}

Write-Host 'Target workspace preparation complete. Close VS Code before importing state.' -ForegroundColor Green
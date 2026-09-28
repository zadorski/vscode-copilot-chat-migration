#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceWslHost,
    [Parameter(Mandatory)]
    [string]$TargetWslHost,
    [Parameter(Mandatory)]
    [string]$SourcePathPrefix,
    [Parameter(Mandatory)]
    [string]$TargetPathPrefix,
    [string]$WorkspaceFileName = 'nix-enabled.code-workspace',
    [string]$SourceWorkspaceStoragePath,
    [string]$TargetWorkspaceStoragePath,
    [string]$OutputPath,
    [switch]$IncludeEmptyWorkspaces,
    [switch]$AllowTargetCollisions,
    [switch]$SkipPrompt
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CopilotChatsMigration.psm1') -Force

if (-not $SourceWorkspaceStoragePath) {
    $SourceWorkspaceStoragePath = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
}
if (-not $TargetWorkspaceStoragePath) {
    $TargetWorkspaceStoragePath = $SourceWorkspaceStoragePath
}
if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) 'copilot-chat-migration-map.json'
}

function ConvertTo-CcmWslUri {
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $encodedAuthority = [Uri]::EscapeDataString("wsl+$HostName")
    $encodedPath = (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "vscode-remote://$encodedAuthority$encodedPath"
}

function ConvertTo-CcmMappedPath {
    param(
        [AllowNull()]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$SourcePrefix,
        [Parameter(Mandatory)]
        [string]$TargetPrefix
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalizedSourcePrefix = $SourcePrefix.TrimEnd('/')
    if ($Path -ne $normalizedSourcePrefix -and
        -not $Path.StartsWith("$normalizedSourcePrefix/", [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $suffix = $Path.Substring($normalizedSourcePrefix.Length).TrimStart('/')
    if ($suffix) {
        return (Join-Path $TargetPrefix $suffix).Replace('\', '/')
    }

    return $TargetPrefix.TrimEnd('/')
}

$sourceRecords = @(
    Get-CcmWorkspaceRecords -WorkspaceStoragePath $SourceWorkspaceStoragePath |
        Where-Object {
            $_.Type -eq 'WSL' -and
            $_.RemoteName -eq $SourceWslHost -and
            ($IncludeEmptyWorkspaces -or $_.HasChatData)
        }
)
$targetRecords = @(Get-CcmWorkspaceRecords -WorkspaceStoragePath $TargetWorkspaceStoragePath)
$targetRecordCollisions = @(
    $targetRecords |
        Group-Object RawUri |
        Where-Object Count -GT 1
)
if ($targetRecordCollisions.Count -gt 0) {
    $collisionUris = $targetRecordCollisions | ForEach-Object Name
    throw "Target workspaceStorage contains duplicate records for: $($collisionUris -join ', '). Resolve duplicates before generating a map."
}

if ($sourceRecords.Count -eq 0) {
    throw "No source WSL workspace records found for host '$SourceWslHost'."
}

$mappings = @(
    foreach ($source in $sourceRecords) {
        $mappedPath = ConvertTo-CcmMappedPath `
            -Path $source.Path `
            -SourcePrefix $SourcePathPrefix `
            -TargetPrefix $TargetPathPrefix

        if (-not $mappedPath) {
            [PSCustomObject]@{
                SourceId               = $source.ID
                SourceUri              = $source.RawUri
                SourcePath             = $source.Path
                SourceWorkspaceKind    = $source.WorkspaceKind
                TargetUri              = $null
                TargetPath             = $null
                TargetId               = $null
                Status                 = 'Source path is outside SourcePathPrefix'
                SourceChatSessionCount = $source.ChatSessionCount
                SourceStateDbMB        = $source.StateDbMB
            }
            continue
        }

        if ($source.WorkspaceKind -eq 'Folder' -and $WorkspaceFileName) {
            $mappedPath = (Join-Path $mappedPath $WorkspaceFileName).Replace('\', '/')
        }

        $targetUri = ConvertTo-CcmWslUri -HostName $TargetWslHost -Path $mappedPath
        $target = $targetRecords | Where-Object { $_.RawUri -eq $targetUri } | Select-Object -First 1

        [PSCustomObject]@{
            SourceId               = $source.ID
            SourceUri              = $source.RawUri
            SourcePath             = $source.Path
            SourceWorkspaceKind    = $source.WorkspaceKind
            TargetUri              = $targetUri
            TargetPath             = $mappedPath
            TargetId               = if ($target) { $target.ID } else { $null }
            Status                 = if ($target) { 'Ready' } else { 'Open target workspace first' }
            SourceChatSessionCount = $source.ChatSessionCount
            SourceStateDbMB        = $source.StateDbMB
        }
    }
)
$mappings = @($mappings | Sort-Object SourcePath, SourceWorkspaceKind, SourceId)

$targetCollisions = @(
    $mappings |
        Where-Object TargetUri |
        Group-Object TargetUri |
        Where-Object Count -GT 1
)
if ($targetCollisions.Count -gt 0) {
    $collisionUris = $targetCollisions | ForEach-Object Name
    if (-not $AllowTargetCollisions) {
        throw "Refusing to write a map with duplicate target URIs: $($collisionUris -join ', '). Re-run with -AllowTargetCollisions only after reviewing the rows."
    }

    foreach ($collision in $targetCollisions) {
        foreach ($mapping in $collision.Group) {
            $mapping.Status = 'Target collision: review mapping'
        }
    }
    Write-Warning "The map contains target collisions and cannot be imported until each collision is resolved."
}

$mappings |
    Format-Table SourcePath, SourceWorkspaceKind, TargetPath, Status, SourceChatSessionCount, SourceStateDbMB -AutoSize

if (-not $SkipPrompt) {
    $confirmed = Read-Host "Write this mapping to '$OutputPath'? (Y/N)"
    if ($confirmed -notmatch '^[Yy]$') {
        Write-Host 'Map generation cancelled.' -ForegroundColor Yellow
        return
    }
}

$map = [ordered]@{
    SchemaVersion               = 1
    GeneratedAtUtc              = (Get-Date).ToUniversalTime().ToString('o')
    SourceWslHost               = $SourceWslHost
    TargetWslHost               = $TargetWslHost
    SourcePathPrefix            = $SourcePathPrefix
    TargetPathPrefix            = $TargetPathPrefix
    WorkspaceFileNameForFolders = $WorkspaceFileName
    Mappings                    = $mappings
}
$outputParent = Split-Path -Path $OutputPath -Parent
if ($outputParent) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}
$map | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Migration map written to: $OutputPath" -ForegroundColor Green
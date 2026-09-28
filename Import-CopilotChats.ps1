#Requires -Version 7.5

<##
.SYNOPSIS
    Imports GitHub Copilot chat history into VS Code workspaceStorage.
.DESCRIPTION
    Imports workspace state from an export ZIP into existing target workspace
    records. A migration map is required for changed remote hosts or paths.
    Target workspace.json files are never overwritten.
.NOTES
    Run this script from Windows PowerShell 7.5+ with VS Code closed.
    Use Chat: Export Chat... for critical conversations before migration.
##>

[CmdletBinding()]
param(
    [string]$ZipPath,
    [string]$MappingPath,
    [string]$WorkspaceStoragePath,
    [string]$BackupPath,
    [switch]$DryRun,
    [switch]$SkipPrompts
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CopilotChatsMigration.psm1') -Force

function Get-CcmWorkspaceFromFolder {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Folder
    )

    $workspaceJsonPath = Join-Path $Folder.FullName 'workspace.json'
    if (-not (Test-Path -LiteralPath $workspaceJsonPath -PathType Leaf)) {
        return $null
    }

    try {
        $json = Get-Content -LiteralPath $workspaceJsonPath -Raw | ConvertFrom-Json
        $rawUri = Get-CcmRawWorkspaceUri -WorkspaceJson $json
        if ([string]::IsNullOrWhiteSpace($rawUri)) {
            return $null
        }

        $info = Get-CcmWorkspaceInfo -RawUri $rawUri -FolderPath $Folder.FullName -Id $Folder.Name
        $stateDb = Get-Item -LiteralPath (Join-Path $Folder.FullName 'state.vscdb') -ErrorAction SilentlyContinue
        $chatFiles = @(Get-ChildItem -LiteralPath (Join-Path $Folder.FullName 'chatSessions') -File -Filter '*.json' -ErrorAction SilentlyContinue)
        return [PSCustomObject]@{
            ExportedFolder = $Folder.FullName
            SourceId = $Folder.Name
            SourceUri = $rawUri
            SourcePath = $info.Path
            SourceWorkspaceKind = $info.WorkspaceKind
            SourceType = $info.Type
            SourceHost = $info.Host
            SourceProject = $info.Project
            SourceRepo = $info.Repo
            SourceChatSessionCount = $chatFiles.Count
            SourceStateDbMB = if ($stateDb) { [math]::Round($stateDb.Length / 1MB, 2) } else { 0 }
        }
    }
    catch {
        Write-Warning "Failed to parse ${workspaceJsonPath}: $($_.Exception.Message)"
        return $null
    }
}

function Get-CcmMapEntry {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [Parameter(Mandatory)]
        [string]$SourceId,
        [Parameter(Mandatory)]
        [string]$SourceUri
    )

    $byId = @($Entries | Where-Object { [string]$_.SourceId -eq $SourceId })
    if ($byId.Count -gt 1) {
        throw "Migration map has duplicate entries for source ID '$SourceId'."
    }
    if ($byId.Count -eq 1) {
        return $byId[0]
    }

    $byUri = @($Entries | Where-Object { [string]$_.SourceUri -eq $SourceUri })
    if ($byUri.Count -gt 1) {
        throw "Migration map has duplicate entries for source URI '$SourceUri'."
    }
    if ($byUri.Count -eq 1) {
        return $byUri[0]
    }

    return $null
}

function Get-CcmTargetRecord {
    param(
        [Parameter(Mandatory)]
        [object[]]$TargetRecords,
        [Parameter(Mandatory)]
        [string]$TargetUri,
        [string]$TargetId
    )

    $candidates = @($TargetRecords | Where-Object { $_.RawUri -eq $TargetUri })
    if ($TargetId) {
        $identified = @($candidates | Where-Object { $_.ID -eq $TargetId })
        if ($identified.Count -eq 1) {
            return $identified[0]
        }
        throw "Target URI '$TargetUri' was not found at the mapped target ID '$TargetId'."
    }

    if ($candidates.Count -eq 0) {
        return $null
    }
    if ($candidates.Count -gt 1) {
        throw "Target URI '$TargetUri' has $($candidates.Count) workspace records. Add TargetId to the migration map before importing."
    }

    return $candidates[0]
}

function New-CcmTargetBackup {
    param(
        [Parameter(Mandatory)]
        [object[]]$Plans,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    if (Test-Path -LiteralPath $OutputPath) {
        throw "Backup path already exists: $OutputPath. Choose a new path so an earlier backup cannot be overwritten."
    }

    $outputParent = Split-Path -Path $OutputPath -Parent
    if ($outputParent) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $tempBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) "VSCode_Copilot_TargetBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
    New-Item -ItemType Directory -Path $tempBackupPath -Force | Out-Null

    try {
        $manifest = [ordered]@{
            SchemaVersion = 1
            CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            TargetWorkspaceStoragePath = $Plans[0].TargetStoragePath
            Workspaces = @()
        }
        $seen = @{}

        foreach ($plan in $Plans) {
            if ($seen.ContainsKey($plan.TargetId)) {
                continue
            }
            $seen[$plan.TargetId] = $true

            $destination = Join-Path $tempBackupPath $plan.TargetId
            Copy-Item -LiteralPath $plan.TargetFolder -Destination $destination -Recurse -Force
            $manifest.Workspaces += [ordered]@{
                TargetId = $plan.TargetId
                TargetUri = $plan.TargetUri
                TargetFolder = $plan.TargetFolder
            }
        }

        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempBackupPath 'backup-manifest.json') -Encoding utf8
        Compress-Archive -Path (Join-Path $tempBackupPath '*') -DestinationPath $OutputPath -CompressionLevel Optimal
    }
    finally {
        if (Test-Path -LiteralPath $tempBackupPath) {
            Remove-Item -LiteralPath $tempBackupPath -Recurse -Force
        }
    }

    return $OutputPath
}

function Copy-CcmWorkspaceState {
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $sourceRoot = $Plan.SourceFolder
    $targetRoot = $Plan.TargetFolder
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse)

    foreach ($sourceFile in $sourceFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName).Replace('\', '/')
        if ($relativePath -eq 'workspace.json') {
            continue
        }

        $destination = Join-Path $targetRoot ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $destinationParent = Split-Path -Path $destination -Parent
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null

        if (-not $Plan.IsExactMatch -and $relativePath -like 'chatSessions/*.json') {
            $content = Get-Content -LiteralPath $sourceFile.FullName -Raw
            $updatedContent = Convert-CcmUriReferences -Content $content -OldUri $Plan.SourceUri -NewUri $Plan.TargetUri
            Set-Content -LiteralPath $destination -Value $updatedContent -NoNewline -Encoding utf8
        }
        else {
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
        }
    }
}

if (-not $ZipPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $openDialog = [System.Windows.Forms.OpenFileDialog]::new()
    $openDialog.Title = 'Select Copilot Chat Export File'
    $openDialog.Filter = 'ZIP files (*.zip)|*.zip'
    $openDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ZipPath = $openDialog.FileName
    }
    else {
        Write-Host 'Import cancelled.' -ForegroundColor Yellow
        return
    }
}

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw "Migration ZIP not found at: $ZipPath"
}

if (-not $WorkspaceStoragePath) {
    $WorkspaceStoragePath = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
}
if (-not (Test-Path -LiteralPath $WorkspaceStoragePath -PathType Container)) {
    throw "VS Code workspaceStorage not found at: $WorkspaceStoragePath"
}

$map = $null
$mapEntries = @()
if ($MappingPath) {
    if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) {
        throw "Migration map not found at: $MappingPath"
    }
    $map = Get-Content -LiteralPath $MappingPath -Raw | ConvertFrom-Json
    $mapEntries = @($map.Mappings)
    if ($mapEntries.Count -eq 0) {
        throw "Migration map contains no mappings: $MappingPath"
    }

    $duplicateTargets = @(
        $mapEntries |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.TargetUri) } |
            Group-Object TargetUri |
            Where-Object Count -gt 1
    )
    if ($duplicateTargets.Count -gt 0) {
        throw "Migration map contains duplicate target URIs: $(($duplicateTargets | ForEach-Object Name) -join ', '). Resolve the map before importing."
    }
}

if (-not $SkipPrompts) {
    Write-Host ''
    Write-Host 'Before importing workspace state:' -ForegroundColor Yellow
    Write-Host '  1. Use Command Palette > Chat: Export Chat... for any remaining critical conversations.' -ForegroundColor Yellow
    Write-Host '  2. Close every VS Code window so workspaceStorage is not being written.' -ForegroundColor Yellow
    $confirmed = Read-Host 'Have you exported critical chats and closed VS Code? (Y/N)'
    if ($confirmed -notmatch '^[Yy]$') {
        Write-Host 'Import cancelled before copying.' -ForegroundColor Yellow
        return
    }
}

$tempExtractPath = Join-Path ([System.IO.Path]::GetTempPath()) "VSCode_Copilot_Import_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null

try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempExtractPath -Force
    $targetRecords = @(Get-CcmWorkspaceRecords -WorkspaceStoragePath $WorkspaceStoragePath)
    $exportedWorkspaces = @(
        Get-ChildItem -LiteralPath $tempExtractPath -Directory |
            ForEach-Object { Get-CcmWorkspaceFromFolder -Folder $_ } |
            Where-Object { $_ }
    )

    if ($exportedWorkspaces.Count -eq 0) {
        throw 'No valid workspace records were found in the export ZIP.'
    }

    $plans = @()
    $skipped = @()
    $errors = @()

    foreach ($source in $exportedWorkspaces) {
        $entry = if ($MappingPath) {
            Get-CcmMapEntry -Entries $mapEntries -SourceId $source.SourceId -SourceUri $source.SourceUri
        }
        else {
            $null
        }

        if ($entry -and [string]$entry.Status -like 'Target collision:*') {
            $errors += "Source '$($source.SourceId)' is marked '$($entry.Status)'."
            continue
        }

        $targetUri = if ($entry) { [string]$entry.TargetUri } else { $source.SourceUri }
        if ([string]::IsNullOrWhiteSpace($targetUri)) {
            $skipped += "Source '$($source.SourceId)' has no target URI."
            continue
        }

        if ($entry -and [string]$entry.Status -eq 'Source path is outside SourcePathPrefix') {
            $skipped += "Source '$($source.SourceId)' is outside SourcePathPrefix."
            continue
        }

        if ($MappingPath -and -not $entry) {
            $errors += "No mapping found for exported source '$($source.SourceId)' ($($source.SourceUri))."
            continue
        }

        try {
            $target = Get-CcmTargetRecord `
                -TargetRecords $targetRecords `
                -TargetUri $targetUri `
                -TargetId $(if ($entry) { [string]$entry.TargetId } else { $null })
        }
        catch {
            $errors += $_.Exception.Message
            continue
        }

        if (-not $target) {
            $errors += "Target workspace is not open in VS Code yet: $targetUri"
            continue
        }

        $plans += [PSCustomObject]@{
            SourceFolder = $source.ExportedFolder
            SourceId = $source.SourceId
            SourceUri = $source.SourceUri
            SourcePath = $source.SourcePath
            SourceProject = $source.SourceProject
            TargetFolder = $target.FolderPath
            TargetId = $target.ID
            TargetUri = $target.RawUri
            TargetPath = $target.Path
            TargetStoragePath = $WorkspaceStoragePath
            IsExactMatch = $source.SourceUri -eq $target.RawUri
            ChatSessionCount = $source.SourceChatSessionCount
            StateDbMB = $source.SourceStateDbMB
        }
    }

    $duplicatePlanTargets = @(
        $plans |
            Group-Object TargetId |
            Where-Object Count -gt 1
    )
    if ($duplicatePlanTargets.Count -gt 0) {
        $errors += "Multiple exported workspaces resolve to the same target record: $(($duplicatePlanTargets | ForEach-Object Name) -join ', ')"
    }

    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error $_ }
        throw 'Import plan is not safe to apply. Resolve the errors and run the importer again.'
    }
    if ($plans.Count -eq 0) {
        throw 'No exported workspaces resolved to importable target records.'
    }

    Write-Host "Resolved $($plans.Count) workspace(s) for import." -ForegroundColor Cyan
    $plans |
        Sort-Object TargetPath |
        Select-Object SourceProject, SourcePath, TargetPath, IsExactMatch, ChatSessionCount, StateDbMB |
        Format-Table -AutoSize

    if ($skipped.Count -gt 0) {
        Write-Host "Skipped $($skipped.Count) workspace(s):" -ForegroundColor Yellow
        $skipped | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    if (-not $SkipPrompts) {
        $proceed = Read-Host "Proceed with $($plans.Count) workspace import(s)? (Y/N)"
        if ($proceed -notmatch '^[Yy]$') {
            Write-Host 'Import cancelled.' -ForegroundColor Yellow
            return
        }
    }

    if ($DryRun) {
        Write-Host '[DRY RUN] Plan validated. No target files or backups were changed.' -ForegroundColor Magenta
        return
    }

    if (-not $BackupPath) {
        $backupParent = Split-Path -Path $ZipPath -Parent
        if (-not $backupParent) {
            $backupParent = (Get-Location).Path
        }
        $BackupPath = Join-Path $backupParent "VSCode_Target_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    }

    Write-Host "Creating target backup at: $BackupPath" -ForegroundColor Cyan
    $createdBackup = New-CcmTargetBackup -Plans $plans -OutputPath $BackupPath
    Write-Host "Target backup created: $createdBackup" -ForegroundColor Green

    $completed = 0
    foreach ($plan in $plans) {
        $completed++
        Write-Host "[$completed/$($plans.Count)] Importing $($plan.SourceProject) -> $($plan.TargetPath)" -ForegroundColor Cyan
        Copy-CcmWorkspaceState -Plan $plan
    }

    Write-Host "Import complete. Imported $($plans.Count) workspace(s)." -ForegroundColor Green
    Write-Host "Target workspace.json files were preserved. Backup: $BackupPath" -ForegroundColor Yellow
}
finally {
    if (Test-Path -LiteralPath $tempExtractPath) {
        Remove-Item -LiteralPath $tempExtractPath -Recurse -Force
    }
}
#Requires -Version 7.5

[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$WorkspaceStoragePath,
    [string[]]$WorkspaceId,
    [switch]$All,
    [switch]$ListOnly,
    [switch]$SkipPrompts
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CopilotChatsMigration.psm1') -Force

if (-not $WorkspaceStoragePath) {
    $WorkspaceStoragePath = Get-CcmDefaultWorkspaceStoragePath
}
if (-not $WorkspaceStoragePath) {
    throw 'Workspace storage path could not be determined. Pass -WorkspaceStoragePath explicitly.'
}

Write-Host "Scanning workspaceStorage at: $WorkspaceStoragePath" -ForegroundColor Cyan
$workspaces = @(Get-CcmWorkspaceRecords -WorkspaceStoragePath $WorkspaceStoragePath)

if ($workspaces.Count -eq 0) {
    Write-Warning "No valid workspaces found."
    return
}

if ($WorkspaceId -and $All) {
    throw 'Use either -WorkspaceId or -All, not both.'
}

Write-Host "Found $($workspaces.Count) workspace(s)." -ForegroundColor Green
$gridColumns = @(
    'Repo',
    'Subproject',
    'Host',
    'Type',
    'WorkspaceKind',
    'HasChatData',
    'ChatSessionCount',
    'StateDbMB',
    'Created',
    'LastUsed',
    'Path',
    'ID',
    'FolderPath',
    'RawUri'
)

if ($ListOnly) {
    $inventory = $workspaces | Sort-Object LastUsed -Descending | Select-Object $gridColumns
    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        $inventory | Out-GridView -Title 'VS Code workspace inventory (read-only; close when finished)' -Wait
    }
    else {
        $inventory | Format-Table -AutoSize
    }
    return
}

if (-not $OutputPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $saveDialog = [System.Windows.Forms.SaveFileDialog]::new()
    $saveDialog.Title = 'Save Copilot Chat Export'
    $saveDialog.Filter = 'ZIP files (*.zip)|*.zip'
    $saveDialog.FileName = "VSCode_Chats_Migration_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $saveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $OutputPath = $saveDialog.FileName
    }
    else {
        Write-Host 'Export cancelled.' -ForegroundColor Yellow
        return
    }
}

$selected = if ($WorkspaceId) {
    $requestedIds = @($WorkspaceId | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $selected = @($workspaces | Where-Object { $requestedIds -contains $_.ID })
    $missingIds = @($requestedIds | Where-Object { $_ -notin $selected.ID })
    if ($missingIds.Count -gt 0) {
        throw "Workspace ID(s) not found: $($missingIds -join ', ')"
    }
    $selected
}
elseif ($All) {
    $workspaces
}
elseif (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    @(
        $workspaces |
            Sort-Object LastUsed -Descending |
            Select-Object $gridColumns |
            Out-GridView -Title 'Select workspaces to export (Ctrl+Click for multiple, then OK)' -PassThru
    )
}
else {
    throw 'Interactive selection requires Out-GridView. Use -All or -WorkspaceId for headless export.'
}

if ($selected.Count -eq 0) {
    Write-Host 'No workspaces selected. Exiting.' -ForegroundColor Yellow
    return
}

Write-Host "Selected $($selected.Count) workspace(s)." -ForegroundColor Cyan
if (-not $SkipPrompts) {
    Write-Host ''
    Write-Host 'Before copying workspace state:' -ForegroundColor Yellow
    Write-Host '  1. Use Command Palette > Chat: Export Chat... for critical conversations.' -ForegroundColor Yellow
    Write-Host '  2. Close every VS Code window so state.vscdb is consistent.' -ForegroundColor Yellow
    $confirmed = Read-Host 'Have you exported critical chats and closed VS Code? (Y/N)'
    if ($confirmed -notmatch '^[Yy]$') {
        Write-Host 'Export cancelled before copying.' -ForegroundColor Yellow
        return
    }
}

Assert-CcmVsCodeClosed -SkipPrompt:$SkipPrompts

$tempExportPath = Join-Path ([System.IO.Path]::GetTempPath()) "VSCode_Chats_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $tempExportPath -Force | Out-Null

try {
    $manifest = [ordered]@{
        SchemaVersion              = 2
        ExportedAtUtc              = (Get-Date).ToUniversalTime().ToString('o')
        SourceWorkspaceStoragePath = $WorkspaceStoragePath
        Workspaces                 = @(
            $selected | ForEach-Object {
                [ordered]@{
                    Id               = $_.ID
                    RawUri           = $_.RawUri
                    DecodedUri       = $_.DecodedUri
                    Type             = $_.Type
                    Host             = $_.Host
                    WorkspaceKind    = $_.WorkspaceKind
                    Path             = $_.Path
                    ChatSessionCount = $_.ChatSessionCount
                    StateDbMB        = $_.StateDbMB
                }
            }
        )
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempExportPath 'migration-manifest.json') -Encoding utf8

    Write-Host 'Copying selected workspaces to a temporary export...' -ForegroundColor Cyan
    foreach ($ws in $selected) {
        Assert-CcmVsCodeClosed -SkipPrompt:$SkipPrompts
        $sourcePath = $ws.FolderPath
        $destPath = Join-Path $tempExportPath $ws.ID
        Write-Host "  Copying: $($ws.Subproject) [$($ws.WorkspaceKind)] ($($ws.Host))..." -ForegroundColor Gray
        Copy-Item -LiteralPath $sourcePath -Destination $destPath -Recurse -Force
    }

    $outputParent = Split-Path -Path $OutputPath -Parent
    if ($outputParent) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    Write-Host "Creating zip archive at: $OutputPath" -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $tempExportPath '*') -DestinationPath $OutputPath -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $tempExportPath) {
        Remove-Item -LiteralPath $tempExportPath -Recurse -Force
    }
}

$zipSize = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1MB, 2)
Write-Host "`nExport complete: $($selected.Count) workspace(s), $zipSize MB" -ForegroundColor Green
Write-Host "Output file: $OutputPath" -ForegroundColor Green
Write-Host 'Keep this ZIP and the Chat: Export Chat JSON files until target validation is complete.' -ForegroundColor Yellow

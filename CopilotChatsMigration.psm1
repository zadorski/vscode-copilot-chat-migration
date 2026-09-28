Set-StrictMode -Version Latest

function Get-CcmJsonPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Get-CcmVsCodeProcesses {
    if ($IsWindows -eq $false) {
        return @()
    }

    @(
        Get-Process -Name @('Code', 'Code - Insiders', 'code-insiders') -ErrorAction SilentlyContinue
    )
}

function Assert-CcmVsCodeClosed {
    [CmdletBinding()]
    param(
        [switch]$SkipPrompt
    )

    $processes = @(Get-CcmVsCodeProcesses)
    if ($processes.Count -eq 0) {
        return
    }

    $processNames = $processes | Select-Object -ExpandProperty ProcessName -Unique
    $message = "VS Code is still running ($($processNames -join ', ')). Close every VS Code window before copying workspaceStorage."
    if ($SkipPrompt) {
        throw "$message Re-run after closing VS Code."
    }

    Write-Warning $message
    $confirmed = Read-Host 'Close VS Code now, then enter Y to recheck (Y/N)'
    if ($confirmed -notmatch '^[Yy]$') {
        throw 'Operation cancelled while VS Code was still running.'
    }

    $remaining = @(Get-CcmVsCodeProcesses)
    if ($remaining.Count -gt 0) {
        $remainingNames = $remaining | Select-Object -ExpandProperty ProcessName -Unique
        throw "VS Code is still running ($($remainingNames -join ', ')). Close it and run the command again."
    }
}

function Get-CcmRawWorkspaceUri {
    param(
        [Parameter(Mandatory)]
        [object]$WorkspaceJson
    )

    foreach ($name in @('folder', 'workspace', 'configuration')) {
        $value = Get-CcmJsonPropertyValue -InputObject $WorkspaceJson -Name $name
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    return $null
}

function Get-CcmWorkspaceInfo {
    param(
        [Parameter(Mandatory)]
        [string]$RawUri,
        [string]$FolderPath,
        [string]$Id
    )

    $decoded = [Uri]::UnescapeDataString($RawUri)
    $type = 'Local'
    $remoteName = $null
    $hostName = 'Local'
    $pathPart = $decoded -replace '^file:///', ''

    if ($decoded -match '^vscode-remote://wsl\+(?<D>[^/]+)(?<R>/.*)') {
        $type = 'WSL'
        $remoteName = $Matches.D
        $hostName = "WSL: $remoteName"
        $pathPart = $Matches.R
    }
    elseif ($decoded -match '^vscode-remote://ssh-remote\+(?<H>[^/]+)(?<R>/.*)') {
        $type = 'SSH'
        $remoteName = $Matches.H
        $hostName = "SSH: $remoteName"
        $pathPart = $Matches.R
    }
    elseif ($decoded -match '^vscode-remote://dev-container\+(?<C>[^/]+)(?<R>/.*)') {
        $type = 'DevContainer'
        $remoteName = $Matches.C
        $hostName = 'Container'
        $pathPart = $Matches.R
    }
    elseif ($decoded -match '^vscode-remote://amlext\+') {
        $type = 'AzureML'
        $hostName = 'AzureML'
    }

    $pathPart = $pathPart.TrimEnd('/')
    $project = Split-Path -Path $pathPart -Leaf
    $repo = Split-Path -Path (Split-Path -Path $pathPart -Parent) -Leaf
    $workspaceKind = if ($pathPart -match '\.code-workspace$') { 'WorkspaceFile' } else { 'Folder' }

    [PSCustomObject]@{
        RawUri        = $RawUri
        DecodedUri    = $decoded
        Type          = $type
        Host          = $hostName
        RemoteName    = $remoteName
        Path          = $pathPart
        Project       = $project
        Repo          = $repo
        WorkspaceKind = $workspaceKind
        FolderPath    = $FolderPath
        ID            = $Id
    }
}

function Get-CcmWorkspaceRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceStoragePath
    )

    if (-not (Test-Path -LiteralPath $WorkspaceStoragePath -PathType Container)) {
        throw "VS Code workspaceStorage not found at: $WorkspaceStoragePath"
    }

    @(
        Get-ChildItem -LiteralPath $WorkspaceStoragePath -Directory | ForEach-Object {
            $folder = $_
            $workspaceJsonPath = Join-Path $folder.FullName 'workspace.json'

            if (-not (Test-Path -LiteralPath $workspaceJsonPath -PathType Leaf)) {
                return
            }

            try {
                $json = Get-Content -LiteralPath $workspaceJsonPath -Raw | ConvertFrom-Json
                $rawUri = Get-CcmRawWorkspaceUri -WorkspaceJson $json

                if ([string]::IsNullOrWhiteSpace($rawUri)) {
                    return
                }

                $info = Get-CcmWorkspaceInfo -RawUri $rawUri -FolderPath $folder.FullName -Id $folder.Name
                $stateDbPath = Join-Path $folder.FullName 'state.vscdb'
                $chatSessionsPath = Join-Path $folder.FullName 'chatSessions'
                $stateDb = Get-Item -LiteralPath $stateDbPath -ErrorAction SilentlyContinue
                $chatFiles = @(Get-ChildItem -LiteralPath $chatSessionsPath -File -Filter '*.json' -ErrorAction SilentlyContinue)
                $chatBytes = if ($chatFiles.Count -gt 0) {
                    ($chatFiles | Measure-Object -Property Length -Sum).Sum
                }
                else {
                    0
                }
                $lastUsed = if ($stateDb) { $stateDb.LastWriteTime } else { $folder.LastWriteTime }

                [PSCustomObject]@{
                    Repo              = $info.Repo
                    Subproject        = $info.Project
                    Host              = $info.Host
                    RemoteName        = $info.RemoteName
                    Type              = $info.Type
                    WorkspaceKind     = $info.WorkspaceKind
                    Path              = $info.Path
                    ID                = $folder.Name
                    HasChatData       = [bool]$stateDb -or (Test-Path -LiteralPath $chatSessionsPath -PathType Container)
                    ChatSessionCount  = $chatFiles.Count
                    ChatBytes         = $chatBytes
                    StateDbMB         = if ($stateDb) { [math]::Round($stateDb.Length / 1MB, 2) } else { 0 }
                    Created           = $folder.CreationTime.ToString('yyyy-MM-dd HH:mm')
                    LastUsed          = $lastUsed.ToString('yyyy-MM-dd HH:mm')
                    FolderPath        = $folder.FullName
                    WorkspaceJsonPath = $workspaceJsonPath
                    RawUri            = $rawUri
                    DecodedUri        = $info.DecodedUri
                }
            }
            catch {
                Write-Verbose "Skipping $($folder.FullName): $($_.Exception.Message)"
            }
        }
    )
}

function Convert-CcmUriReferences {
    param(
        [Parameter(Mandatory)]
        [string]$Content,
        [Parameter(Mandatory)]
        [string]$OldUri,
        [Parameter(Mandatory)]
        [string]$NewUri
    )

    $oldDecoded = [Uri]::UnescapeDataString($OldUri)
    $newDecoded = [Uri]::UnescapeDataString($NewUri)
    $pairs = @(
        @{ Old = $OldUri; New = $NewUri }
        @{ Old = $oldDecoded; New = $newDecoded }
        @{ Old = [Uri]::EscapeDataString($OldUri); New = [Uri]::EscapeDataString($NewUri) }
        @{ Old = [Uri]::EscapeDataString($oldDecoded); New = [Uri]::EscapeDataString($newDecoded) }
    )

    $updated = $Content
    foreach ($pair in $pairs) {
        if ([string]::IsNullOrEmpty($pair.Old)) {
            continue
        }

        $updated = $updated -replace [Regex]::Escape($pair.Old), { $pair.New }
    }

    return $updated
}

Export-ModuleMember -Function @(
    'Assert-CcmVsCodeClosed',
    'Convert-CcmUriReferences',
    'Get-CcmVsCodeProcesses',
    'Get-CcmRawWorkspaceUri',
    'Get-CcmWorkspaceInfo',
    'Get-CcmWorkspaceRecords'
)
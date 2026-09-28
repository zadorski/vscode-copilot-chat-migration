# Copilot Chat Migration

PowerShell 7.5+ scripts for migrating GitHub Copilot chat state between VS Code workspace records when a WSL distro or Linux path changes.

This fork is maintained on the `main` branch:

`https://github.com/zadorski/vscode-copilot-chat-migration`

## What the scripts protect

VS Code stores workspace state under:

```text
%APPDATA%\Code\User\workspaceStorage
```

Each directory has a generated ID, but `workspace.json` contains the workspace URI that controls how VS Code finds the record. The scripts therefore map full source URIs to full target URIs rather than matching by project name or folder ID.

The importer:

- preserves the target `workspace.json`
- backs up every target workspace before writing
- refuses duplicate source-to-target mappings
- supports `-DryRun` without changing target storage
- rewrites mapped `chatSessions/*.json` URI references
- copies `state.vscdb` and other workspace state files as binary data

Do not import two source records into one target record. Duplicate source records are common after repeatedly opening a folder and a `.code-workspace` file; review those collisions explicitly.

## Requirements

- Windows host with VS Code workspace storage
- PowerShell 7.5 or newer
- `Out-GridView` for the interactive exporter
- VS Code closed before exporting or importing workspace state
- the target WSL distro already installed
- the target `code-wsl` command available inside the target distro

The scripts are intended to run on Windows PowerShell 7.5+, not inside WSL. The scripts accept explicit storage paths for testing from Linux `pwsh`.

## Repeatable WSL migration

The example below migrates `nixos` to `welnix` and changes `/home/nixos/workspaces` to `/home/nixos/workspace`. Adjust the values to your environment.

Set the working directory to the extracted repository:

```powershell
cd C:\path\to\vscode-copilot-chat-migration
$storage = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
```

### 1. Export source workspace state

First create a ZIP. The grid shows workspace kind, chat count, database size, raw URI, and storage folder.

```powershell
.\Export-CopilotChats.ps1 -OutputPath C:\backup\nixos-copilot-chats.zip
```

Before copying, the exporter asks you to:

1. Run `Chat: Export Chat...` for critical conversations and keep those JSON files separately.
2. Close every VS Code window.

For a read-only inventory, use:

```powershell
.\Export-CopilotChats.ps1 -WorkspaceStoragePath $storage -ListOnly
```

Keep both the ZIP and the individual `Chat: Export Chat...` JSON files until the target has been validated.

### 2. Generate the deterministic URI map

```powershell
.\New-CopilotChatMigrationMap.ps1 `
  -SourceWslHost nixos `
  -TargetWslHost welnix `
  -SourcePathPrefix /home/nixos/workspaces `
  -TargetPathPrefix /home/nixos/workspace `
  -WorkspaceFileName nix-enabled.code-workspace `
  -SourceWorkspaceStoragePath $storage `
  -TargetWorkspaceStoragePath $storage `
  -OutputPath C:\backup\nixos-to-welnix-map.json
```

Folder workspaces are mapped to `nix-enabled.code-workspace` under the target path. Existing workspace-file records retain their file name. The map records source ID, source URI, target URI, target ID when known, and a status.

The generator refuses duplicate target URIs by default. To write a review-only map containing collisions, use:

```powershell
.\New-CopilotChatMigrationMap.ps1 ... -AllowTargetCollisions
```

Do not import that map. Open the JSON, keep one source record per target URI, or correct the target URI/ID, then rerun the importer. This is especially important when one source record is a folder and another is a workspace file for the same project. The importer refuses unresolved collision statuses and duplicate target URIs.

Records outside `SourcePathPrefix` are listed as skipped. Generate a separate map with a different prefix if those records are also needed.

### 3. Open every target workspace once

Review the target list without opening anything:

```powershell
.\Prepare-CopilotChatTargets.ps1 -MappingPath C:\backup\nixos-to-welnix-map.json
```

Then open the targets in one pass:

```powershell
.\Prepare-CopilotChatTargets.ps1 `
  -MappingPath C:\backup\nixos-to-welnix-map.json `
  -Open
```

The helper calls `wsl.exe` and runs `WSLEDIT_CONTEXT=code-wsl code-wsl ...` inside `welnix`. This avoids the context-sensitive `code` alias selecting the wrong distro. Let VS Code finish creating the target workspace records, then close every VS Code window again.

### 4. Validate the import plan

The importer re-reads target workspace storage after preparation; map statuses such as `Open target workspace first` are therefore not trusted as proof that a target exists.

```powershell
.\Import-CopilotChats.ps1 `
  -ZipPath C:\backup\nixos-copilot-chats.zip `
  -MappingPath C:\backup\nixos-to-welnix-map.json `
  -WorkspaceStoragePath $storage `
  -DryRun
```

Dry-run checks that every selected source record has exactly one target record, that no two exports target the same record, and that all collision statuses are resolved. It creates no backup and writes no workspace state.

### 5. Import with a target backup

```powershell
.\Import-CopilotChats.ps1 `
  -ZipPath C:\backup\nixos-copilot-chats.zip `
  -MappingPath C:\backup\nixos-to-welnix-map.json `
  -WorkspaceStoragePath $storage `
  -BackupPath C:\backup\welnix-target-before-import.zip
```

The importer prompts for confirmation that critical chats were exported and VS Code is closed. It creates the target backup before copying any source files. `workspace.json` remains the target version so the generated target workspace ID and URI stay intact.

## Rollback

Close VS Code. Extract the backup ZIP to a temporary directory, then restore the target workspace folders from the backup manifest. The archive contains the original target folder IDs and complete folder contents, including the original `workspace.json`.

```powershell
$restore = Join-Path $env:TEMP 'vscode-copilot-target-restore'
Remove-Item $restore -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive C:\backup\welnix-target-before-import.zip -DestinationPath $restore
Copy-Item "$restore\<target-id>\*" "$storage\<target-id>" -Recurse -Force
```

Restore each target ID listed in `backup-manifest.json`, then reopen VS Code through the target distro.

## Settings Sync and chat export

Use local ZIP migration plus `Chat: Export Chat...` JSON files as the primary recovery path for workspace-local chat state. Settings Sync is useful afterward for settings, extensions, keybindings, and other synchronized configuration, but it should not be treated as the transport for this workspace-storage migration. Enable or reconcile Settings Sync after the local target has been validated.

## Other workspace types

The shared parser recognizes local folders, WSL, SSH Remote, Dev Containers, and Azure ML workspace URIs. The deterministic WSL map generator only creates mappings for the requested source WSL host. Exact URI imports can still be run without `-MappingPath` when source and target URIs are unchanged.

## Validation

Parse-check all scripts with PowerShell 7.5:

```powershell
Get-ChildItem *.ps1 | ForEach-Object {
  [scriptblock]::Create((Get-Content $_.FullName -Raw)) | Out-Null
}
```

For a real inventory, use `Export-CopilotChats.ps1 -ListOnly`. For a real WSL migration, generate the map, review collisions, prepare targets, run importer `-DryRun`, and only then perform the backed-up import.
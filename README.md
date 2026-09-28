# Copilot Chat Migration

PowerShell 7.5+ tools for moving VS Code workspace state when a WSL distro or Linux path changes. The maintained fork is on [`main`](https://github.com/zadorski/vscode-copilot-chat-migration).

VS Code stores these records in `%APPDATA%\Code\User\workspaceStorage`. Folder names are generated IDs; `workspace.json` contains the URI that identifies the workspace. The map therefore uses full source and target URIs, not project names.

## Requirements

- Windows Terminal running PowerShell 7.5 or newer
- `Out-GridView` for interactive export selection
- VS Code closed before export, backup, or import writes
- the target WSL distro and its `code-wsl` command already available

Run real migrations from the Windows host. `-Open` rejects WSL-side PowerShell; Linux `pwsh` is supported only for explicit-path tests and dry-run inspection.

## Windows Terminal workflow

This example migrates `nixos` to `welnix`, `/home/nixos/workspaces` to `/home/nixos/workspace`, and folder records to `nix-enabled.code-workspace`.

```powershell
Set-Location C:\path\to\vscode-copilot-chat-migration
$storage = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
$backup = 'C:\backup'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
```

1. Export and keep the ZIP plus separate `Chat: Export Chat...` JSON files for critical conversations:

```powershell
.\Export-CopilotChats.ps1 -OutputPath "$backup\nixos-copilot-chats.zip"
```

2. Generate and review the URI map. The generator sorts mappings, URI-escapes path segments, and refuses duplicate target URIs by default:

```powershell
.\New-CopilotChatMigrationMap.ps1 `
  -SourceWslHost nixos -TargetWslHost welnix `
  -SourcePathPrefix /home/nixos/workspaces `
  -TargetPathPrefix /home/nixos/workspace `
  -WorkspaceFileName nix-enabled.code-workspace `
  -SourceWorkspaceStoragePath $storage `
  -TargetWorkspaceStoragePath $storage `
  -OutputPath "$backup\nixos-to-welnix-map.json"
```

Use `-AllowTargetCollisions` only to produce a review map. Do not import it until every source maps to one target record.

3. Review target records, then open only missing targets:

```powershell
.\Prepare-CopilotChatTargets.ps1 -MappingPath "$backup\nixos-to-welnix-map.json"
.\Prepare-CopilotChatTargets.ps1 `
  -MappingPath "$backup\nixos-to-welnix-map.json" -Open
```

The helper invokes `wsl.exe` for `welnix`, clears inherited remote CLI and askpass endpoints, verifies `code-wsl` and the target path inside that distro, and then opens the target. Wait for VS Code to create the records, then close every VS Code window.

4. Validate the import without changing storage:

```powershell
.\Import-CopilotChats.ps1 `
  -ZipPath "$backup\nixos-copilot-chats.zip" `
  -MappingPath "$backup\nixos-to-welnix-map.json" `
  -WorkspaceStoragePath $storage -DryRun
```

5. Perform the backed-up import. An explicit backup path must be new; an existing path is refused:

```powershell
.\Import-CopilotChats.ps1 `
  -ZipPath "$backup\nixos-copilot-chats.zip" `
  -MappingPath "$backup\nixos-to-welnix-map.json" `
  -WorkspaceStoragePath $storage `
  -BackupPath "$backup\welnix-target-before-import.zip"
```

## Safety and idempotency

- Export and import recheck actual Windows VS Code processes immediately before copying; `-SkipPrompts` does not bypass that check.
- Import creates a complete target backup first, preserves target `workspace.json`, removes all other target state, copies source state, and rewrites mapped `chatSessions/*.json` URI references.
- Repeating the same import converges to the same target file snapshot. Automatically named backups include milliseconds and a GUID; explicit backups never overwrite an existing file.
- Preparation skips target URIs already present and refuses duplicate map or target-storage records.
- `state.vscdb` and other non-chat files are copied as binary data. No import occurs unless every selected source has exactly one target.

## Rollback and Copilot Chat recovery

Keep the export ZIP, separate chat exports, and target backup until validation is complete. To roll back, close VS Code, expand the backup, and restore each target ID listed in `backup-manifest.json`:

```powershell
$restore = Join-Path $env:TEMP 'vscode-copilot-target-restore'
Remove-Item $restore -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive "$backup\welnix-target-before-import.zip" -DestinationPath $restore
Copy-Item "$restore\<target-id>\*" "$storage\<target-id>" -Recurse -Force
```

Use `Chat: Export Chat...` before migration and `Chat: Import Chat...` afterward for individual critical conversations. Settings Sync remains useful for settings, extensions, and keybindings, but is not the transport for workspace-local `workspaceStorage` state. Use the repository helper or `code-wsl` for target opens; do not run a generic `code` command from the source distro and assume it selects the target endpoint.

## Development

The standalone flake provides PowerShell, PSScriptAnalyzer 1.25.0, and the formatter:

```bash
nix develop .#powershell --command powershell-scriptanalyzer \
  CopilotChatsMigration.psm1 Export-CopilotChats.ps1 Import-CopilotChats.ps1 \
  New-CopilotChatMigrationMap.ps1 Prepare-CopilotChatTargets.ps1
nix develop .#powershell --command powershell-format \
  CopilotChatsMigration.psm1 Export-CopilotChats.ps1 Import-CopilotChats.ps1 \
  New-CopilotChatMigrationMap.ps1 Prepare-CopilotChatTargets.ps1
nix flake check
nix fmt
```

The repository also carries `.editorconfig` and `nix-enabled.code-workspace` generated for this workspace by `nix-deterministic-agent`.

## Credits

The original exporter/importer and early fixes were authored by Alexander (Sasha) Ostrikov. The WSL URI mapping, target preparation, backup/rollback flow, and audit fixes in this fork were contributed by Pavel Zadorski.

## Extra credit disclaimer

This is an independent community fork. It is not affiliated with GitHub, Microsoft, VS Code, or the Copilot team. VS Code and Copilot Chat workspace storage is internal implementation detail and may change; keep independent exports and backups.

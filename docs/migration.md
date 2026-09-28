# Migration Guide

The scripts move VS Code workspace records stored in the platform's VS Code `User/workspaceStorage` directory. Use Windows PowerShell 7.5+ for a real Windows migration, keep VS Code closed before copying state, and keep a separate `Chat: Export Chat...` JSON file for critical conversations.

The examples use placeholders. Replace the paths, host names, and workspace filename with values from your own machines.

The direct scripts live under `packages/copilot-chats-migration/`. The packaged commands are available after entering `nix develop` or running `just shell`.

## 1. Set up the session

```powershell
Set-Location C:\path\to\vscode-copilot-chat-migration
$storage = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
$backup = 'C:\backup'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
```

Use the direct `.ps1` files from the package directory, or the packaged command names after entering `nix develop`. Pass `-WorkspaceStoragePath` explicitly when the platform default is not correct.

## 2. Export source state

```powershell
.\packages\copilot-chats-migration\Export-CopilotChats.ps1 -WorkspaceStoragePath $storage -OutputPath "$backup\copilot-chats.zip"
```

The interactive selector chooses workspace records, not project names. `-ListOnly` produces a read-only inventory. On hosts without `Out-GridView`, use `-All` or one or more `-WorkspaceId` values instead:

```powershell
.\packages\copilot-chats-migration\Export-CopilotChats.ps1 -WorkspaceStoragePath $storage -OutputPath "$backup\copilot-chats.zip" -All -SkipPrompts
.\packages\copilot-chats-migration\Export-CopilotChats.ps1 -WorkspaceStoragePath $storage -OutputPath "$backup\selected.zip" -WorkspaceId 0123456789abcdef -SkipPrompts
```

Close VS Code after selection and before the copy begins.

## 3. Generate and review a map

```powershell
.\packages\copilot-chats-migration\New-CopilotChatMigrationMap.ps1 `
  -SourceWslHost old-distro -TargetWslHost new-distro `
  -SourcePathPrefix /home/user/workspaces `
  -TargetPathPrefix /home/user/workspaces `
  -WorkspaceFileName project.code-workspace `
  -SourceWorkspaceStoragePath $storage `
  -TargetWorkspaceStoragePath $storage `
  -OutputPath "$backup\migration-map.json"
```

The generator uses complete workspace URIs, escapes path segments, sorts output, and refuses duplicate target URIs. Use `-AllowTargetCollisions` only for a review map; the importer refuses unresolved collision statuses.

## 4. Prepare target records

Review the missing records first:

```powershell
.\packages\copilot-chats-migration\Prepare-CopilotChatTargets.ps1 `
  -MappingPath "$backup\migration-map.json" `
  -WorkspaceStoragePath $storage
```

Open missing records with a VS Code-compatible command. The command receives the target workspace URI after the arguments:

```powershell
.\packages\copilot-chats-migration\Prepare-CopilotChatTargets.ps1 `
  -MappingPath "$backup\migration-map.json" `
  -WorkspaceStoragePath $storage `
  -Open -OpenCommand code -OpenArgument @('--new-window')
```

Use `-OpenCommand` for another executable or wrapper script. The helper does not assume a particular remote CLI, shell integration, distro, or operating system. Wait for VS Code to create missing records, then close VS Code again.

## 5. Validate and import

```powershell
.\packages\copilot-chats-migration\Import-CopilotChats.ps1 `
  -ZipPath "$backup\copilot-chats.zip" `
  -MappingPath "$backup\migration-map.json" `
  -WorkspaceStoragePath $storage `
  -DryRun
```

If the plan is correct, import with a new explicit backup path:

```powershell
.\packages\copilot-chats-migration\Import-CopilotChats.ps1 `
  -ZipPath "$backup\copilot-chats.zip" `
  -MappingPath "$backup\migration-map.json" `
  -WorkspaceStoragePath $storage `
  -BackupPath "$backup\target-before-import.zip"
```

The importer re-reads target storage, requires exactly one target per selected source, preserves each target `workspace.json`, and rewrites mapped chat-session URI references.

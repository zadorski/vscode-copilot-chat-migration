# Copilot Chat Migration

PowerShell 7.5+ scripts for moving VS Code `workspaceStorage` records when a remote host, distro, or workspace path changes.

> **Note**
> The migration flow is tested with agentic flow, but normal caution still applies. 
> Use the provided safeguards: keep an independent chat export and backup, 
> review the migration map, and inspect the dry-run before importing.

The workflow exports selected records, maps source workspace URIs to target URIs, prepares missing target records, then dry-runs and imports the state. The importer preserves each target `workspace.json`, rewrites chat-session URIs, replaces stale target files, and creates a backup before copying.

Start an export from PowerShell:

```powershell
pwsh -NoProfile `
  -File ./packages/copilot-chats-migration/Export-CopilotChats.ps1 `
  -WorkspaceStoragePath /path/to/workspaceStorage `
  -OutputPath /path/to/copilot-chats.zip
```

Use [the migration guide](docs/migration.md) for the map, preparation, dry-run, and import steps. Keep an independent `Chat: Export Chat...` JSON export for critical conversations.

- [Safety and recovery](docs/safety-and-recovery.md)
- [Packaging and development](docs/development.md)

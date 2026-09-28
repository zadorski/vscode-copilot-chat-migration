# VS Code Copilot Chat Migration

PowerShell 7.5+ tools for exporting and importing VS Code `workspaceStorage` state when remote hosts or paths change.

Run `nix develop` for the packaged commands and validation tools. The shortest safe workflow is export, map, prepare, dry-run, then import with a new backup path.

- [Migration guide](docs/migration.md)
- [Safety and recovery](docs/safety-and-recovery.md)
- [Packaging and development](docs/development.md)

This independent community project is not affiliated with GitHub, Microsoft, VS Code, or the Copilot team. VS Code workspace storage is an internal implementation detail; keep independent chat exports and backups.

# Packaging and Development

The repository keeps payload, packaging, and root-wide agreements separate:

- `packages/copilot-chats-migration/` contains the PowerShell module and migration scripts.
- `packages/copilot-chats-migration/package.nix` installs that payload and exposes the migration scripts using their PowerShell Verb-Noun names.
- `packages/powershell-scriptanalyzer/` packages `Invoke-ScriptAnalyzer` and the pinned PSScriptAnalyzer module.
- `packages/powershell-format/` packages `Invoke-Formatter` and reuses the analyzer package's module path.
- `flake.nix` only connects the package tree to the default development shell, checks, and the Nix formatter.
- `justfile` provides short root-level commands without duplicating package logic.

Enter the default shell to access the packaged migration commands and validation tools:

```bash
just shell
Export-CopilotChats -?
Import-CopilotChats -?
New-CopilotChatMigrationMap -?
Prepare-CopilotChatTargets -?
```

Run focused validation from the repository root:

```bash
just lint
just format-powershell
just check
just format
just build
just build-scriptanalyzer
just build-format
```

The packages are available as `.#copilot-chats-migration`, `.#powershell-scriptanalyzer`, and `.#powershell-format`. No environment-specific launcher, distro name, or shell integration is part of the package contract.

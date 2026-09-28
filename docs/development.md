# Packaging and Development

The repository keeps implementation and Nix packaging separate:

- `sources/package.nix` installs the PowerShell module and migration scripts, then exposes wrapper commands for export, import, map generation, and target preparation.
- `sources/tooling.nix` packages PSScriptAnalyzer 1.25.0 and exposes the analyzer and formatter wrappers.
- `flake.nix` only connects those sources to packages, the default development shell, checks, and the Nix formatter.

Enter the default shell to access the packaged migration commands and validation tools:

```bash
nix develop
copilot-chat-export -?
copilot-chat-import -?
copilot-chat-map -?
copilot-chat-prepare -?
```

Run focused validation from the repository root:

```bash
nix develop --command powershell-scriptanalyzer \
  CopilotChatsMigration.psm1 Export-CopilotChats.ps1 Import-CopilotChats.ps1 \
  New-CopilotChatMigrationMap.ps1 Prepare-CopilotChatTargets.ps1
nix develop --command powershell-format \
  CopilotChatsMigration.psm1 Export-CopilotChats.ps1 Import-CopilotChats.ps1 \
  New-CopilotChatMigrationMap.ps1 Prepare-CopilotChatTargets.ps1
nix flake check
nix fmt -- flake.nix sources/package.nix sources/tooling.nix
```

The package is available as `.#vscode-copilot-chat-migration`; the analyzer and tooling are available as `.#powershell-analyzer` and `.#powershell-tools`. No environment-specific launcher, distro name, or shell integration is part of the package contract.

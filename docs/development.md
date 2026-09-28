# Packaging and Development

The repository keeps payload, packaging, and root-wide agreements separate:

- `packages/vscode-copilot-chat-migration/` contains the PowerShell module and migration scripts.
- `packages/vscode-copilot-chat-migration/package.nix` installs that payload and exposes wrapper commands for export, import, map generation, and target preparation.
- `packages/powershell-tools/` contains the analyzer and formatter wrappers plus their package-local derivation.
- `flake.nix` only connects the package tree to the default development shell, checks, and the Nix formatter.
- `justfile` provides short root-level commands without duplicating package logic.

Enter the default shell to access the packaged migration commands and validation tools:

```bash
just shell
copilot-chat-export -?
copilot-chat-import -?
copilot-chat-map -?
copilot-chat-prepare -?
```

Run focused validation from the repository root:

```bash
just lint
just format-powershell
just check
just format
just build
just build-tools
```

The packages are available as `.#vscode-copilot-chat-migration` and `.#powershell-tools`. No environment-specific launcher, distro name, or shell integration is part of the package contract.

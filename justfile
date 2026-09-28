set shell := ["bash", "-euo", "pipefail", "-c"]

scripts := "packages/vscode-copilot-chat-migration/CopilotChatsMigration.psm1 packages/vscode-copilot-chat-migration/Export-CopilotChats.ps1 packages/vscode-copilot-chat-migration/Import-CopilotChats.ps1 packages/vscode-copilot-chat-migration/New-CopilotChatMigrationMap.ps1 packages/vscode-copilot-chat-migration/Prepare-CopilotChatTargets.ps1 packages/powershell-tools/scripts/powershell-scriptanalyzer.ps1 packages/powershell-tools/scripts/powershell-format.ps1"
nix_files := "flake.nix packages/vscode-copilot-chat-migration/package.nix packages/powershell-tools/package.nix"

_default:
    @just --list

shell:
    nix develop

format:
    nix fmt -- {{nix_files}}

lint:
    nix develop --command powershell-scriptanalyzer {{scripts}}

format-powershell:
    nix develop --command powershell-format {{scripts}}

check:
    nix flake check

build:
    nix build .#vscode-copilot-chat-migration

build-tools:
    nix build .#powershell-tools

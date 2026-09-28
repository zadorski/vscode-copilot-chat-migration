set shell := ["bash", "-euo", "pipefail", "-c"]

scripts := "packages/copilot-chats-migration/CopilotChatsMigration.psm1 packages/copilot-chats-migration/Export-CopilotChats.ps1 packages/copilot-chats-migration/Import-CopilotChats.ps1 packages/copilot-chats-migration/New-CopilotChatMigrationMap.ps1 packages/copilot-chats-migration/Prepare-CopilotChatTargets.ps1 packages/powershell-scriptanalyzer/scripts/Invoke-ScriptAnalyzer.ps1 packages/powershell-format/scripts/Invoke-Formatter.ps1"
nix_files := "flake.nix packages/copilot-chats-migration/package.nix packages/powershell-scriptanalyzer/package.nix packages/powershell-format/package.nix"

_default:
    @just --list

shell:
    nix develop

format:
    nix fmt -- {{nix_files}}

lint:
    nix develop --command Invoke-ScriptAnalyzer {{scripts}}

format-powershell:
    nix develop --command Invoke-Formatter {{scripts}}

check:
    nix flake check

build:
    nix build .#copilot-chats-migration

build-scriptanalyzer:
    nix build .#powershell-scriptanalyzer

build-format:
    nix build .#powershell-format

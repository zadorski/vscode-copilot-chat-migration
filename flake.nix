{
  description = "Safe PowerShell tooling for VS Code Copilot Chat workspace migration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
  };

  outputs =
    inputs@{ self, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

      perSystem =
        { config, pkgs, ... }:
        let
          migrationScripts = map (name: "${self}/packages/vscode-copilot-chat-migration/${name}") [
            "CopilotChatsMigration.psm1"
            "Export-CopilotChats.ps1"
            "Import-CopilotChats.ps1"
            "New-CopilotChatMigrationMap.ps1"
            "Prepare-CopilotChatTargets.ps1"
          ];
        in
        {
          pkgsDirectory = self + "/packages";

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.powershell
              config.packages.vscode-copilot-chat-migration
              config.packages.powershell-tools
            ];
            POWERSHELL_TELEMETRY_OPTOUT = "1";
            POWERSHELL_UPDATECHECK = "Off";
          };

          checks.powershell-scripts =
            pkgs.runCommand "vscode-copilot-chat-migration-check"
              {
                nativeBuildInputs = [
                  pkgs.powershell
                  config.packages.powershell-tools
                ];
              }
              ''
                powershell-scriptanalyzer ${pkgs.lib.escapeShellArgs migrationScripts}
                powershell-format ${pkgs.lib.escapeShellArgs migrationScripts}
                touch "$out"
              '';

          formatter = pkgs.nixfmt;
        };
    };
}

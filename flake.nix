{
  description = "Safe PowerShell tooling for VS Code Copilot Chat workspace migration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      toolingSource = import ./sources/tooling.nix;
      packageSource = import ./sources/package.nix;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          tooling = toolingSource { inherit pkgs; };
          migration = packageSource { inherit pkgs tooling; };
        in
        {
          default = migration.package;
          vscode-copilot-chat-migration = migration.package;
          powershell-analyzer = tooling.analyzer;
          powershell-tools = tooling.powershellTools;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          tooling = toolingSource { inherit pkgs; };
          migration = packageSource { inherit pkgs tooling; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.powershell
              migration.package
              tooling.powershellTools
            ];
            POWERSHELL_TELEMETRY_OPTOUT = "1";
            POWERSHELL_UPDATECHECK = "Off";
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          tooling = toolingSource { inherit pkgs; };
          migration = packageSource { inherit pkgs tooling; };
        in
        {
          powershell-scripts = migration.check;
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}

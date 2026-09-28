{ pkgs, tooling }:

let
  lib = pkgs.lib;
  pname = "vscode-copilot-chat-migration";
  sourceRoot = ../.;
  sourceFiles = [
    "CopilotChatsMigration.psm1"
    "Export-CopilotChats.ps1"
    "Import-CopilotChats.ps1"
    "New-CopilotChatMigrationMap.ps1"
    "Prepare-CopilotChatTargets.ps1"
  ];
  commandScripts = {
    copilot-chat-export = "Export-CopilotChats.ps1";
    copilot-chat-import = "Import-CopilotChats.ps1";
    copilot-chat-map = "New-CopilotChatMigrationMap.ps1";
    copilot-chat-prepare = "Prepare-CopilotChatTargets.ps1";
  };
  package = pkgs.stdenvNoCC.mkDerivation {
    inherit pname;
    version = "0.1.0";
    src = sourceRoot;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;

    installPhase = ''
      share="$out/share/${pname}"
      install -d "$share"
      ${lib.concatMapStringsSep "\n" (
        file: "install -Dm644 \"$src/${file}\" \"$share/${file}\""
      ) sourceFiles}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (command: script: ''
          makeWrapper "${pkgs.powershell}/bin/pwsh" "$out/bin/${command}" \
            --add-flags "-NoLogo -NoProfile -File $share/${script}"
        '') commandScripts
      )}
    '';

    meta = {
      description = "PowerShell tools for migrating VS Code workspace state";
      homepage = "https://github.com/zadorski/vscode-copilot-chat-migration";
      mainProgram = "copilot-chat-export";
      platforms = lib.platforms.all;
    };
  };
  scriptPaths = map (name: "${sourceRoot}/${name}") sourceFiles;
  check =
    pkgs.runCommand "${pname}-check"
      {
        nativeBuildInputs = [
          pkgs.powershell
          tooling.powershellTools
        ];
      }
      ''
        powershell-scriptanalyzer ${lib.escapeShellArgs scriptPaths}
        powershell-format ${lib.escapeShellArgs scriptPaths}
        touch "$out"
      '';
in
{
  inherit check package sourceFiles;
}

{
  lib,
  makeWrapper,
  powershell,
  stdenvNoCC,
  ...
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "copilot-chats-migration";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    share="$out/share/${finalAttrs.pname}"
    install -d "$share"
    install -Dm644 CopilotChatsMigration.psm1 "$share/CopilotChatsMigration.psm1"
    install -Dm644 Export-CopilotChats.ps1 "$share/Export-CopilotChats.ps1"
    install -Dm644 Import-CopilotChats.ps1 "$share/Import-CopilotChats.ps1"
    install -Dm644 New-CopilotChatMigrationMap.ps1 "$share/New-CopilotChatMigrationMap.ps1"
    install -Dm644 Prepare-CopilotChatTargets.ps1 "$share/Prepare-CopilotChatTargets.ps1"

    makeWrapper "${powershell}/bin/pwsh" "$out/bin/Export-CopilotChats" \
      --add-flags "-NoLogo -NoProfile -File $share/Export-CopilotChats.ps1"
    makeWrapper "${powershell}/bin/pwsh" "$out/bin/Import-CopilotChats" \
      --add-flags "-NoLogo -NoProfile -File $share/Import-CopilotChats.ps1"
    makeWrapper "${powershell}/bin/pwsh" "$out/bin/New-CopilotChatMigrationMap" \
      --add-flags "-NoLogo -NoProfile -File $share/New-CopilotChatMigrationMap.ps1"
    makeWrapper "${powershell}/bin/pwsh" "$out/bin/Prepare-CopilotChatTargets" \
      --add-flags "-NoLogo -NoProfile -File $share/Prepare-CopilotChatTargets.ps1"
    runHook postInstall
  '';

  meta = {
    description = "PowerShell commands for migrating VS Code Copilot Chat workspace state";
    homepage = "https://github.com/zadorski/vscode-copilot-chat-migration";
    mainProgram = "Export-CopilotChats";
    platforms = lib.platforms.all;
  };
})

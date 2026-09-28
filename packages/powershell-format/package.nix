{
  lib,
  powershell,
  powershell-scriptanalyzer,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "powershell-format";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/Invoke-Formatter "$out/bin/Invoke-Formatter"
    install -Dm644 scripts/Invoke-Formatter.ps1 "$out/share/${finalAttrs.pname}/Invoke-Formatter.ps1"
    substituteInPlace "$out/bin/Invoke-Formatter" \
      --subst-var-by pwsh "${powershell}/bin/pwsh" \
      --subst-var-by toolsShare "$out/share/${finalAttrs.pname}" \
      --subst-var-by psModulePath "${powershell-scriptanalyzer.psModulePath}" \
      --subst-var-by psScriptAnalyzerModule "${powershell-scriptanalyzer.psScriptAnalyzerModule}"
    runHook postInstall
  '';

  meta = {
    description = "PowerShell Invoke-Formatter command using PSScriptAnalyzer";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    mainProgram = "Invoke-Formatter";
    platforms = lib.platforms.all;
  };
})

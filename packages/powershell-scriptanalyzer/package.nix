{
  fetchzip,
  lib,
  powershell,
  stdenvNoCC,
}:

let
  analyzerVersion = "1.25.0";
  analyzerSource = fetchzip {
    url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${analyzerVersion}";
    hash = "sha256-OEyOGPyFatNo68Jlx1G8UOKQu83UScZMRQ3TlzKxjl0=";
    extension = "zip";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "powershell-scriptanalyzer";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;
  doInstallCheck = true;
  nativeInstallCheckInputs = [ powershell ];

  installPhase = ''
    runHook preInstall
    module_root="$out/share/powershell/Modules/PSScriptAnalyzer/${analyzerVersion}"
    mkdir -p "$module_root"
    cp -R --no-preserve=mode,ownership "${analyzerSource}"/* "$module_root/"
    rm -rf "$module_root/compatibility_profiles"
    install -Dm755 bin/Invoke-ScriptAnalyzer "$out/bin/Invoke-ScriptAnalyzer"
    install -Dm644 scripts/Invoke-ScriptAnalyzer.ps1 "$out/share/${finalAttrs.pname}/Invoke-ScriptAnalyzer.ps1"
    substituteInPlace "$out/bin/Invoke-ScriptAnalyzer" \
      --subst-var-by pwsh "${powershell}/bin/pwsh" \
      --subst-var-by toolsShare "$out/share/${finalAttrs.pname}" \
      --subst-var-by psModulePath "$out/share/powershell/Modules" \
      --subst-var-by psScriptAnalyzerModule "$module_root/PSScriptAnalyzer.psd1"
    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    module_manifest="$out/share/powershell/Modules/PSScriptAnalyzer/${analyzerVersion}/PSScriptAnalyzer.psd1"
    module_version="$(${powershell}/bin/pwsh -NoLogo -NoProfile -NonInteractive -Command "(Import-PowerShellDataFile -LiteralPath '$module_manifest').ModuleVersion.ToString()")"
    if [[ "$module_version" != "${analyzerVersion}" ]]; then
      echo "expected PSScriptAnalyzer module version ${analyzerVersion}, got $module_version" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  passthru = {
    psModulePath = "${finalAttrs.finalPackage}/share/powershell/Modules";
    psScriptAnalyzerModule = "${finalAttrs.finalPackage}/share/powershell/Modules/PSScriptAnalyzer/${analyzerVersion}/PSScriptAnalyzer.psd1";
  };

  meta = {
    description = "PowerShell Invoke-ScriptAnalyzer command with PSScriptAnalyzer";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    license = lib.licenses.mit;
    mainProgram = "Invoke-ScriptAnalyzer";
    platforms = lib.platforms.all;
  };
})

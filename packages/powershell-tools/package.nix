{
  fetchzip,
  lib,
  powershell,
  stdenvNoCC,
  ...
}:

let
  analyzerVersion = "1.25.0";
  powershellAnalyzer = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "powershell-analyzer";
    version = analyzerVersion;

    src = fetchzip {
      url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${finalAttrs.version}";
      hash = "sha256-OEyOGPyFatNo68Jlx1G8UOKQu83UScZMRQ3TlzKxjl0=";
      extension = "zip";
      stripRoot = false;
    };

    dontBuild = true;
    doInstallCheck = true;
    nativeInstallCheckInputs = [ powershell ];

    installPhase = ''
      runHook preInstall
      module_root="$out/share/powershell/Modules/PSScriptAnalyzer/${finalAttrs.version}"
      mkdir -p "$module_root"
      cp -R --no-preserve=mode,ownership . "$module_root/"
      rm -rf "$module_root/compatibility_profiles"
      runHook postInstall
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      module_manifest="$out/share/powershell/Modules/PSScriptAnalyzer/${finalAttrs.version}/PSScriptAnalyzer.psd1"
      module_version="$(${powershell}/bin/pwsh -NoLogo -NoProfile -NonInteractive -Command "(Import-PowerShellDataFile -LiteralPath '$module_manifest').ModuleVersion.ToString()")"
      if [[ "$module_version" != "${finalAttrs.version}" ]]; then
        echo "expected PSScriptAnalyzer module version ${finalAttrs.version}, got $module_version" >&2
        exit 1
      fi
      runHook postInstallCheck
    '';

    meta = {
      description = "PowerShell static analyzer packaged from PowerShell Gallery";
      homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
    };
  });
  psModulePath = "${powershellAnalyzer}/share/powershell/Modules";
  psScriptAnalyzerModule = "${psModulePath}/PSScriptAnalyzer/${analyzerVersion}/PSScriptAnalyzer.psd1";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "powershell-tools";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/powershell-scriptanalyzer "$out/bin/powershell-scriptanalyzer"
    install -Dm755 bin/powershell-format "$out/bin/powershell-format"
    install -Dm644 scripts/powershell-scriptanalyzer.ps1 "$out/share/${finalAttrs.pname}/powershell-scriptanalyzer.ps1"
    install -Dm644 scripts/powershell-format.ps1 "$out/share/${finalAttrs.pname}/powershell-format.ps1"
    substituteInPlace "$out/bin/powershell-scriptanalyzer" "$out/bin/powershell-format" \
      --subst-var-by pwsh "${powershell}/bin/pwsh" \
      --subst-var-by toolsShare "$out/share/${finalAttrs.pname}" \
      --subst-var-by psModulePath "${psModulePath}" \
      --subst-var-by psScriptAnalyzerModule "${psScriptAnalyzerModule}"
    runHook postInstall
  '';

  meta = {
    description = "PowerShell analyzer and formatter wrapper commands for this repository";
    mainProgram = "powershell-scriptanalyzer";
    platforms = lib.platforms.all;
  };
})

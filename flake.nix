{
  description = "Safe PowerShell tooling for VS Code Copilot Chat workspace migration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPackages =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          analyzerVersion = "1.25.0";
          powershellAnalyzer = pkgs.stdenvNoCC.mkDerivation {
            pname = "powershell-analyzer";
            version = analyzerVersion;

            src = pkgs.fetchzip {
              url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${analyzerVersion}";
              hash = "sha256-OEyOGPyFatNo68Jlx1G8UOKQu83UScZMRQ3TlzKxjl0=";
              extension = "zip";
              stripRoot = false;
            };

            dontBuild = true;
            doInstallCheck = true;
            nativeInstallCheckInputs = [ pkgs.powershell ];

            installPhase = ''
              runHook preInstall
              module_root="$out/share/powershell/Modules/PSScriptAnalyzer/${analyzerVersion}"
              mkdir -p "$module_root"
              cp -R --no-preserve=mode,ownership . "$module_root/"
              rm -rf "$module_root/compatibility_profiles"
              runHook postInstall
            '';

            installCheckPhase = ''
              runHook preInstallCheck
              module_manifest="$out/share/powershell/Modules/PSScriptAnalyzer/${analyzerVersion}/PSScriptAnalyzer.psd1"
              module_version="$(${pkgs.powershell}/bin/pwsh -NoLogo -NoProfile -NonInteractive -Command "(Import-PowerShellDataFile -LiteralPath '$module_manifest').ModuleVersion.ToString()")"
              if [[ "$module_version" != "${analyzerVersion}" ]]; then
                echo "expected PSScriptAnalyzer module version ${analyzerVersion}, got $module_version" >&2
                exit 1
              fi
              runHook postInstallCheck
            '';

            meta = {
              description = "PowerShell static analyzer packaged from PowerShell Gallery";
              homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.all;
            };
          };

          modulePath = "${powershellAnalyzer}/share/powershell/Modules";
          analyzerModule = "${modulePath}/PSScriptAnalyzer/${analyzerVersion}/PSScriptAnalyzer.psd1";
          scriptAnalyzer = pkgs.writeText "powershell-scriptanalyzer.ps1" ''
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Paths
            )

            if (-not (Test-Path -LiteralPath $env:PSSCRIPTANALYZER_MODULE)) {
                Write-Error "PSScriptAnalyzer is required but is unavailable in this environment."
                exit 2
            }

            Import-Module -Name $env:PSSCRIPTANALYZER_MODULE -Force
            $allResults = @()

            foreach ($path in $Paths) {
                if (-not (Test-Path -LiteralPath $path)) {
                    continue
                }

                $results = Invoke-ScriptAnalyzer -Path $path -Settings PSGallery -ExcludeRule PSUseSingularNouns
                if ($results) {
                    $allResults += $results
                }
            }

            if ($allResults.Count -gt 0) {
                $allResults | Format-Table -AutoSize
                Write-Host "PSScriptAnalyzer found $($allResults.Count) issue(s)" -ForegroundColor Red
                exit 1
            }

            Write-Host "PSScriptAnalyzer: No issues found" -ForegroundColor Green
          '';
          formatter = pkgs.writeText "powershell-format.ps1" ''
            param(
                [switch]$Write,

                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Paths
            )

            if (-not (Test-Path -LiteralPath $env:PSSCRIPTANALYZER_MODULE)) {
                Write-Error "PSScriptAnalyzer is required but is unavailable in this environment."
                exit 2
            }

            Import-Module -Name $env:PSSCRIPTANALYZER_MODULE -Force
            $formatDrift = @()

            foreach ($path in $Paths) {
                if (-not (Test-Path -LiteralPath $path)) {
                    continue
                }

                $original = Get-Content -LiteralPath $path -Raw
                $formatted = Invoke-Formatter -ScriptDefinition $original -Settings CodeFormatting

                if ($formatted -ne $original) {
                    if ($Write) {
                        [System.IO.File]::WriteAllText($path, $formatted, [System.Text.UTF8Encoding]::new($false))
                        continue
                    }

                    $formatDrift += [PSCustomObject]@{
                        ScriptName = Split-Path -Leaf $path
                        Path       = $path
                    }
                }
            }

            if ($formatDrift.Count -gt 0) {
                $formatDrift | Format-Table -AutoSize
                Write-Host "PowerShell formatter found $($formatDrift.Count) file(s) with formatting drift" -ForegroundColor Red
                exit 1
            }

            if ($Write) {
                exit 0
            }

            Write-Host "PowerShell formatter: No formatting drift found" -ForegroundColor Green
          '';
          powershellLinter = pkgs.symlinkJoin {
            name = "powershell-linter";
            paths = [
              (pkgs.writeShellScriptBin "powershell-scriptanalyzer" ''
                set -euo pipefail
                export PSSCRIPTANALYZER_MODULE="${analyzerModule}"
                export PSModulePath="${modulePath}:''${PSModulePath:-}"
                exec "${pkgs.powershell}/bin/pwsh" -NoProfile -NonInteractive -File "${scriptAnalyzer}" "$@"
              '')
              (pkgs.writeShellScriptBin "powershell-format" ''
                set -euo pipefail
                export PSSCRIPTANALYZER_MODULE="${analyzerModule}"
                export PSModulePath="${modulePath}:''${PSModulePath:-}"
                exec "${pkgs.powershell}/bin/pwsh" -NoProfile -NonInteractive -File "${formatter}" "$@"
              '')
            ];
            meta.description = "PowerShell analyzer and formatter wrappers for this repository";
          };
        in
        {
          inherit powershellAnalyzer powershellLinter;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          packages = mkPackages system;
        in
        {
          default = packages.powershellLinter;
          powershell-analyzer = packages.powershellAnalyzer;
          powershell-linter = packages.powershellLinter;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          packages = mkPackages system;
        in
        {
          powershell = pkgs.mkShell {
            packages = [
              pkgs.powershell
              packages.powershellLinter
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
          packages = mkPackages system;
          scriptPaths = map (name: "${self}/${name}") [
            "CopilotChatsMigration.psm1"
            "Export-CopilotChats.ps1"
            "Import-CopilotChats.ps1"
            "New-CopilotChatMigrationMap.ps1"
            "Prepare-CopilotChatTargets.ps1"
          ];
          scriptArguments = pkgs.lib.escapeShellArgs scriptPaths;
        in
        {
          powershell-scripts =
            pkgs.runCommand "copilot-chat-migration-powershell-check"
              {
                nativeBuildInputs = [
                  pkgs.powershell
                  packages.powershellLinter
                ];
              }
              ''
                powershell-scriptanalyzer ${scriptArguments}
                powershell-format ${scriptArguments}
                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}

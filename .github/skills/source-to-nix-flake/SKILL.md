---
name: source-to-nix-flake
description: Turn a small source repository into a discoverable, reproducible Nix flake with explicit app, tooling, shell, and check boundaries.
---

# Source Repository To Nix Flake

Use this workflow when a repository starts as scripts, source files, and README documentation and needs reproducible Nix packaging without making Nix a prerequisite for ordinary use.

## Design goals

- Keep the source payload easy to find and usable directly.
- Make package outputs discoverable without a manual export list.
- Separate the user-facing application from validation or development tools.
- Give the flake explicit inputs, outputs, supported systems, checks, and a development shell.
- Keep the README about the use case; put Nix workflow details in development documentation.

## Workflow

### 1. Inventory the source

Identify the real entry points, supporting modules, external runtime dependencies, supported operating systems, and existing behavioral checks. Preserve the source behavior first. Do not begin by wrapping every file or inventing a new command name.

For a script repository, distinguish:

- payload files installed for end users
- command wrappers or launchers
- formatters, analyzers, test runners, and other maintainer tools
- user-facing documentation versus packaging documentation

### 2. Choose public boundaries

Name each installable package after one coherent user-facing capability. Avoid an ambiguous aggregate such as `tools` when the repository contains independently useful commands.

A useful shape is:

```text
packages/<main-capability>/package.nix
packages/<validation-command>/package.nix
packages/<formatter-command>/package.nix
```

Use lower-case hyphenated names for Nix package attributes. Keep language-specific command naming in the payload. For PowerShell, public commands should retain Verb-Noun names such as `Export-CopilotChats`, `Invoke-ScriptAnalyzer`, and `Invoke-Formatter`.

### 3. Use automatic package discovery

Prefer `flake-parts` with `pkgs-by-name-for-flake-parts` for a repository whose packages live under `packages/`:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  flake-parts.url = "github:hercules-ci/flake-parts";
  pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
};

outputs = inputs@{ self, ... }:
  inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    imports = [ inputs.pkgs-by-name-for-flake-parts.flakeModule ];

    perSystem = { ... }:
      {
        pkgsDirectory = self + "/packages";
      };
  };
```

Each `packages/<name>/package.nix` becomes a package output named `<name>`. Do not duplicate this with manual `import ./sources/*.nix` or a hand-maintained `packages = { ... };` list.

### 4. Keep payload and derivation together

Put the scripts, module files, wrapper sources, and `package.nix` beside one another. Install only the intended payload files with explicit `install` commands. This keeps source reachability obvious and prevents unrelated repository files from entering a package closure.

For an external module or archive:

- pin its version and fixed-output hash
- verify the installed manifest/version in `installCheckPhase`
- keep the external module in the package that owns the command using it
- expose only narrow internal metadata when another local package genuinely needs it

A formatter that uses an analyzer package can receive that package as a function argument and consume passthru paths such as `psModulePath` or `psScriptAnalyzerModule`. Do not expose a second public package merely to pass an internal file path.

### 5. Make the flake boundary explicit

Use `perSystem` for the development shell, checks, and formatter. The shell should contain the main package and each independently useful validation package. Checks should execute the packaged commands, not an undeclared host installation.

Keep the root task runner thin. Recipes may call `nix develop`, `nix build`, `nix flake check`, and `nix fmt`, but package logic belongs in package derivations and flake checks.

### 6. Preserve a Nix-agnostic user path

The README should answer four questions in a few lines:

1. What problem does the project solve?
2. What does the workflow do?
3. What is the shortest direct command to start?
4. Where are the detailed safety and migration steps?

Use a direct language-runtime command in the README, for example a `pwsh -File ./packages/<main-capability>/...` invocation. State that Nix is optional for direct use. Put the Nix rationale, package outputs, shell commands, and validation recipes in `docs/development.md`.

Explain the benefit for newcomers in a short note: Nix pins dependencies, makes the app/tool boundary discoverable, provides the same development commands on declared systems, and gives the repository a reproducible shell and checks. Do not claim broader platform support than the flake declares; the source runtime and the Nix package systems can have different support sets.

### 7. Validate in narrowing-to-broadening order

Run the cheapest focused checks first, then the complete flake surface:

```bash
just format
just lint
just format-powershell
nix flake check --no-build
nix build .#<main-capability> .#<validation-command> .#<formatter-command> --no-link
nix flake check --all-systems
nix flake show --json
```

Also run behavior-scoped tests for the original source behavior. For migration or stateful scripts, include idempotency, deterministic output, headless mode, collision handling, and generic opener/launcher tests as applicable.

Verify the public surface with `nix flake show --json`; verify the development shell exposes the intended command names. Scan documentation and source for stale package names and private machine, distro, launcher, or workspace assumptions.

### 8. Respect Git and repository mechanics

Pure flake evaluation may only see the repository snapshot available to Nix. Stage new or moved package files before relying on a pure evaluation. Check ignored paths explicitly; repositories often ignore `bin/` globally, so package-owned executable wrappers may require a targeted `git add -f`.

Finish with:

```bash
git diff --cached --check
git status --short
git diff --cached --stat
```

Do not commit generated `result` links, temporary exports, or unrelated user changes.

## Completion checklist

- [ ] Source payload remains directly usable without Nix.
- [ ] Each public capability has one discoverable package directory.
- [ ] No manual package export list duplicates directory discovery.
- [ ] Public command names follow the source ecosystem's conventions.
- [ ] App and tooling packages have clear boundaries.
- [ ] External dependencies are pinned and version-checked.
- [ ] The dev shell and flake checks use packaged commands.
- [ ] README is short, scenario-first, and Nix-agnostic.
- [ ] Development docs explain why Nix is present and link to detailed usage.
- [ ] Native and all-system checks, package builds, and behavior tests pass.
- [ ] Staged diff is clean and no private environment assumptions remain.

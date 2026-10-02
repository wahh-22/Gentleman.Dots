# Lazygit blue theme

## Objective
Install Lazygit with a blue UI derived from Pi's `gentleman-blue` palette whenever Gentleman.Dots is installed using Home Manager or the interactive installer.

## Context and constraints
- Branch `wahh` was clean before this task document was created.
- Lazygit is already present in `flake.nix` and installer dependency lists. The missing piece is configuration deployment, not another binary.
- Reference palette: local Pi `~/.pi/agent/themes/gentleman-blue.json` (`#05070F`, `#347AFF`, `#DBE9FF`, `#5CE1FF`, etc.). Keep a repo-owned Lazygit asset; do not depend on that local Pi file during installation.
- On macOS without XDG_CONFIG_HOME, `lazygit -cd` resolves to `~/Library/Application Support/lazygit`; use the correct platform-specific destination and preserve existing unrelated user settings where feasible.
- User expressly chose both Home Manager and the interactive installer. Do not apply the installer or Home Manager switch to the live machine as a test. Do not push or create a PR.

## Scope and acceptance
- Repo-owned Lazygit theme based on Pi blue, with readable contrast and valid Lazygit config keys.
- Home Manager installs the configuration on supported systems without duplicate package declarations or broken evaluation.
- Interactive installer deploys the same theme on its supported platforms, including when the Lazygit binary is already installed.
- Focused automated tests cover the install wiring and failure/overwrite behavior as appropriate. Run applicable Go and Nix structural/evaluation checks; report unavailable checks honestly.

## Work units
- [x] **LBT-1: Theme asset and Home Manager wiring.** Route: delegated worker (multi-file writer trigger: theme asset + Nix module/flake + focused check). Test-first where meaningful; otherwise structural checks for passive configuration. Verify config content, correct macOS/Linux locations, and evaluation. Commit as one conventional work unit; record hash and check results here.
- [ ] **LBT-2: Interactive installer integration.** Route: delegated worker (multi-file writer trigger: Go installer + tests). Add a focused deterministic test and observe RED, implement and observe GREEN, include alternate/failure cases and run focused suite. Commit as one conventional work unit; record hash and check results here.

## Review/delivery
- Forecast: approximately 200–350 authored diff lines, excluding this progress document. Delivery strategy: ask-on-risk if cumulative authored lines exceed ~400; otherwise keep one reviewable feature branch. Review candidate is a work-unit commit or PR slice, not a checkbox. RDD is on globally; assess actual candidate and follow native authority after a verified work unit.
- Engram mirror `odd/lazygit-blue-theme/tasks`: pending. The Engram server refused cross-project saves from this home-directory session (isolated session registration unavailable). Local document is the surviving authority until a project-scoped session can mirror it.

## Progress and next step
- LBT-1: repo-owned `config/lazygit/config.yml` and macOS Home Manager default-path wiring added. Home Manager refuses an existing unmanaged config rather than silently replacing or merging it; a custom `XDG_CONFIG_HOME` requires manual destination adjustment. Flake only supports Darwin. YAML/theme-key structural check, `nix-instantiate --parse flake.nix`, and `git diff --check` passed. Git-staged flake evaluation attempted but Nix daemon refused connection; no switch performed. Commit: pending.
- Next: implement LBT-2 separately, then verify both paths.

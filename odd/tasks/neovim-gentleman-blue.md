# Neovim Gentleman Blue

## Objective
Create and activate a repository-owned Neovim colorscheme matching the active Pi `gentleman-blue` palette.

## Problem and rationale
Neovim currently selects `gentleman-kanagawa-blur`, while Pi and other tools use Gentleman Blue. Copy the semantic palette into the deployed Neovim configuration instead of depending on a local Pi installation. Use solid backgrounds for fidelity to Pi; preserve other selectable Neovim themes.

## Scope and constraints
- Add `nvim/colors/gentleman-blue.lua` with core editor, syntax, diagnostic, UI, terminal colors, and a blue Snacks dashboard header.
- Select it through `nvim/lua/plugins/colorscheme.lua` without removing the other theme definitions.
- Existing `nvim.nix` deploys the entire `nvim` tree; no deployment change is planned.
- Do not modify the external Pi theme file.
- Delivery strategy: ask-on-risk. Forecast: approximately 180–280 authored diff lines; one cohesive work unit.

## Tasks
- [ ] NGB-1: Implement and activate the colorscheme. Route: delegated `gentle-ai-worker` because two non-trivial files change. Checks: Neovim headless startup and representative highlight/terminal palette assertions; syntax and diff integrity checks. A deterministic visual palette has no existing project test harness; a headless assertion can provide meaningful RED/GREEN if runnable. Commit evidence: pending; do not mark done until verified and a work-unit commit is authorized.

## Acceptance criteria
- `:colorscheme gentleman-blue` loads without errors and LazyVim selects it.
- Normal, selection, float, syntax, diagnostic, diff and terminal colors reflect Pi's blue palette with legible contrasts.
- The Kali logo on the Snacks dashboard uses primary blue (`#347AFF`), without changing violet `Title` headings elsewhere.
- Other themes remain installed and selectable; no runtime dependency on `~/.pi/agent`.

## Progress and evidence
- Read-only exploration found Pi palette in `~/.pi/agent/themes/gentleman-blue.json` and current selection in `nvim/lua/plugins/colorscheme.lua`.
- NGB-1 implementation is present in `nvim/colors/gentleman-blue.lua` and `nvim/lua/plugins/colorscheme.lua`; still in progress. User requested the Kali dashboard logo in primary blue. Snacks links `SnacksDashboardHeader` to `Title` by default; the dedicated override is `#347AFF` while generic `Title` remains violet. The isolated assertion showed RED before the edit and GREEN afterward; Lua syntax and diff whitespace checks passed.
- Writer observed RED (`E185` before adding theme), GREEN (headless palette assertions), Lua syntax and diff checks. Independent verifier confirmed source palette and activation, with a ShaDa shutdown warning (`E137/E136`) on one concurrent invocation; isolated headless invocation with `-i NONE` produced no output or reported failure, but the tool did not expose a numeric exit code. Interactive LazyVim appearance was not tested.
- Native review `review-1012cec6b3febb38` approved and acknowledged the original three-path candidate; one non-blocking startup-coverage warning remains. ASSESS over untracked files was unassessable; an independent verifier ran. Later progress notes in this document are outside that frozen review candidate.
- User selected Home Manager activation. Backed up the prior local Neovim directory to `~/.config/nvim.before-gentleman-blue-20261002-161023`, then `nix run github:nix-community/home-manager -- switch --flake "path:$PWD#gentleman" -b backup` completed. This also activated other Home Manager modules and services according to the command output.
- Independent verifier confirmed both deployed files byte-for-byte match their repository versions. Static installed config selects `gentleman-blue`; interactive appearance and full LazyVim runtime startup remain unverified because startup may bootstrap/update plugins and is not read-only.
- The updated theme was copied directly to `~/.config/nvim/colors/gentleman-blue.lua` after backing up the prior file as `~/.config/nvim/colors/gentleman-blue.lua.before-blue-logo-20261002-162355`. Independent verification confirmed the installed file matches the repository and the installed highlight is blue; full plugin startup and visual appearance remain unchecked.
- Native review of this revised candidate stopped at `managed_assets_outdated` before lineage creation; no approval exists for the follow-up. No managed-assets sync was run in that session because it changed scope beyond the logo adjustment. The user has now explicitly authorized committing the three pending Neovim paths; final headless verification and commit evidence are pending.

## Next step
Repeat isolated headless palette and syntax checks, then commit only this Neovim colorscheme, its LazyVim selection, and this task document; no push requested. Interactive visual inspection and any blocked native review remain separately pending.

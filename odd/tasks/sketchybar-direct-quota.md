# SketchyBar direct AI quota fetch

Replace the opencode-quota cache path of the SketchyBar AI quota panels with the
QuotaShell method: direct HTTPS GETs to each provider's usage endpoint.

## Specs

- S1: "para los datos de los proveedores en sketchy bar de limites de ia, utiliza el mismo metodo que en ~/wahh22/quota-shell porque como esta ahora da muchos problemas y desconexiones". OpenAI/Codex (`https://chatgpt.com/backend-api/wham/usage`, `ChatGPT-Account-Id`) and OpenCode Go (`https://opencode.ai/zen/go/v1/usage`) are fetched directly; opencode-quota is no longer used.
- S2: Claude: "Directo como QuotaShell (Recomendado)" — "Usa el token OAuth del llavero, llamada GET con intervalo mínimo; los datos locales quedan como respaldo si falla (429/red)." Endpoint `https://api.anthropic.com/api/oauth/usage?cedar_ember=1` with `anthropic-beta: oauth-2025-04-20`.
- S3: Copilot: "Quitar el panel" — "Eliminar Copilot de la barra."
- S4: Like QuotaShell: no redirects, no retries, bounded timeouts, no token renewal; failures (401/403/429/5xx/network/invalid data) keep the last readings with their original age; credentials never reach process arguments, caches or logs.

## Tasks

- T1 (S1, S2, S4) inline: `plugins/ai_quota_fetch.sh` fetcher + normalized snapshot cache; `ai_quota.sh` renders OpenAI, Claude and OpenCode Go from it (Claude keeps local fallbacks); tests. Commit: c514412, 3307064, c3a28d5, 51221f4
- T2 (S3) inline: remove Copilot panel, mode and theme color. Commit: c514412

## Log

- L1: "para los datos de los proveedores en sketchy bar de limites de ia, utiliza el mismo metodo que en ~/wahh22/quota-shell porque como esta ahora da muchos problemas y desconexiones"
- L2: Path resolved to `~/wahh22/quotashell` (Kotlin Android app). Live probes: Codex 200 (weekly window only in `primary_window`), OpenCode Go 200, Claude OAuth usage 200 with Claude Code keychain token.
- L3: User answers: Claude "Directo como QuotaShell (Recomendado)"; Copilot "Quitar el panel".
- L4: Deployed to ~/.config/sketchybar; live bar: Claude 39%|67%, OpenAI 80% (weekly-only, collapsed), OpenCode Go 100%|100%, Copilot gone; all fetch statuses ok. Fixed a leftover .state label masking the missing OpenAI 5h window (3307064).
- L5: Native review (risk/resilience/reliability) required one correction: curl --disable + --retry 0, reject malformed present windows (c3a28d5). Approved and acknowledged. Advisory follow-up: a keychain prompt from `security` could block the Claude fetch (ai_quota_fetch.sh:136).
- L6: Independent verify found 2 P2 defects (non-object windows / unparsable resets silently dropped; interval not rechecked under lock). Fixed in 51221f4; re-verify: S1-S4 PASS; second native review approved and acknowledged. Advisories (not blocking): unbounded keychain lookup; clock-rollback edge in fetch_due.

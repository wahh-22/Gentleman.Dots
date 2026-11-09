#!/bin/bash

set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN="$ROOT/sketchybar/plugins/ai_quota.sh"
STATUSLINE="$ROOT/claude/statusline.sh"
CONFIG="$ROOT/sketchybar/sketchybarrc"
TEST_DIR="$(mktemp -d)"
BIN_DIR="$TEST_DIR/bin"
LOG_FILE="$TEST_DIR/sketchybar.log"
NETWORK_LOG="$TEST_DIR/network.log"
NOW=2000000000

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$3"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail "$3"
  fi
}

mkdir -p "$BIN_DIR" "$TEST_DIR/home" "$TEST_DIR/cache"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--query" ]; then
  printf '%s\n' '{"label":{"value":"--","color":"0xffdbe9ff"},"icon":{"value":"x","color":"0xffff9f1c","font":"test"},"geometry":{"background":{"border_color":"0xffff9f1c"}}}'
  exit 0
fi
printf '%s\n' "$*" >> "$LOG_FILE"
EOF

FIXTURES="$TEST_DIR/fixtures"
mkdir -p "$FIXTURES"

# curl stub: logs argv and the stdin config separately, then serves a fixture
# body and status for the requested provider ("fail" simulates a network error).
cat > "$BIN_DIR/curl" <<'EOF'
#!/bin/bash
config="$(cat)"
printf 'ARGS %s\n' "$*" >> "$NETWORK_LOG"
printf 'CONFIG %s\n' "$config" | tr '\n' ' ' >> "$NETWORK_LOG"
printf '\n' >> "$NETWORK_LOG"
out="" prev="" url=""
for arg in "$@"; do
  [ "$prev" = "--output" ] && out="$arg"
  prev="$arg"
  url="$arg"
done
case "$url" in
  *chatgpt.com*) provider=openai ;;
  *anthropic.com*) provider=claude ;;
  *opencode.ai*) provider=opencode-go ;;
  *) exit 6 ;;
esac
code="$(cat "$FIXTURES/$provider.code" 2>/dev/null || printf 200)"
[ "$code" = "fail" ] && exit 7
cp "$FIXTURES/$provider.json" "$out"
printf '%s' "$code"
EOF

cat > "$BIN_DIR/security" <<'EOF'
#!/bin/bash
[ -f "$FIXTURES/keychain.json" ] || exit 44
cat "$FIXTURES/keychain.json"
EOF

chmod +x "$BIN_DIR"/*
[ -x "$STATUSLINE" ] || fail "status line source must be executable"
[ -x "$PLUGIN" ] || fail "quota plugin source must be executable"

export PATH="$BIN_DIR:$PATH"
export HOME="$TEST_DIR/home"
export XDG_CACHE_HOME="$TEST_DIR/cache"
unset XDG_DATA_HOME CODEX_HOME
export LOG_FILE NETWORK_LOG FIXTURES
export AI_QUOTA_NOW="$NOW"

status_input=$(cat <<EOF
{
  "model":{"display_name":"Claude Test"},
  "workspace":{"current_dir":"$TEST_DIR"},
  "cost":{"total_lines_added":1,"total_lines_removed":2},
  "context_window":{"context_window_size":100,"current_usage":{"input_tokens":10}},
  "account":{"secret":"must-not-persist"},
  "rate_limits":{
    "five_hour":{"used_percentage":25,"resets_at":$((NOW + 3600))},
    "seven_day":{"used_percentage":40,"resets_at":$((NOW + 86400))}
  }
}
EOF
)

CLAUDE_STATUSLINE_NOW="$NOW" "$STATUSLINE" <<< "$status_input" >/dev/null
RATE_FILE="$XDG_CACHE_HOME/sketchybar/claude-rate-limits.json"
MCP_FILE="$XDG_CACHE_HOME/claude/statusline-mcp"
[ -f "$RATE_FILE" ] || fail "status line must create the rate-limit sidecar"
[ "$(stat -c '%a' "$RATE_FILE" 2>/dev/null || stat -f '%Lp' "$RATE_FILE")" = "600" ] || fail "sidecar mode must be 0600"
[ -f "$MCP_FILE" ] || fail "status line must create the MCP cache under XDG cache"
[ "$(stat -c '%a' "$MCP_FILE" 2>/dev/null || stat -f '%Lp' "$MCP_FILE")" = "600" ] || fail "MCP cache mode must be 0600"
[ "$(stat -c '%a' "$XDG_CACHE_HOME/claude" 2>/dev/null || stat -f '%Lp' "$XDG_CACHE_HOME/claude")" = "700" ] || fail "MCP cache directory mode must be 0700"
assert_not_contains "$STATUSLINE" '/tmp/claude_mcp_cache' "status line must not reference the shared legacy MCP cache"
jq -e 'keys == ["captured_at","five_hour","seven_day"] and .five_hour.used_percentage == 25 and .seven_day.used_percentage == 40' "$RATE_FILE" >/dev/null || fail "sidecar must contain only projected rate limits"
assert_not_contains "$RATE_FILE" 'secret' "sidecar must never persist account or session data"

partial_input=$(printf '%s' "$status_input" | jq '.rate_limits.five_hour.used_percentage = 101')
CLAUDE_STATUSLINE_NOW="$((NOW + 1))" "$STATUSLINE" <<< "$partial_input" >/dev/null
jq -e 'has("five_hour") | not' "$RATE_FILE" >/dev/null || fail "invalid 5h data must be omitted independently"
jq -e 'has("seven_day")' "$RATE_FILE" >/dev/null || fail "valid 7d data must survive an invalid 5h window"
invalid_input=$(printf '%s' "$partial_input" | jq 'del(.rate_limits.seven_day)')
CLAUDE_STATUSLINE_NOW="$((NOW + 2))" "$STATUSLINE" <<< "$invalid_input" >/dev/null
jq -e '.captured_at == ($now + 1)' --argjson now "$NOW" "$RATE_FILE" >/dev/null || fail "fully invalid input must not replace the last usable cache"
CLAUDE_STATUSLINE_NOW="$NOW" "$STATUSLINE" <<< "$status_input" >/dev/null


CACHE="$XDG_CACHE_HOME/sketchybar"
CLAUDE_TOKEN="claude-secret-token"
CODEX_TOKEN="codex-secret-token"
GO_KEY="go-secret-key"

run_plugin() {
  : > "$LOG_FILE"
  AI_QUOTA_NOW="$1" "$PLUGIN" "${@:2}"
}

network_calls() {
  grep -c '^ARGS' "$NETWORK_LOG" 2>/dev/null || true
}

# ── Claude: direct OAuth read ───────────────────────────────────────────────
printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":%s}}' "$CLAUDE_TOKEN" "$(((NOW + 7200) * 1000))" > "$FIXTURES/keychain.json"
cat > "$FIXTURES/claude.json" <<'EOF'
{"five_hour":{"utilization":10.0,"resets_at":"2033-05-18T04:33:20.831054+00:00"},"seven_day":{"utilization":20.0,"resets_at":"2033-05-19T03:33:20.5+00:00"},"extra_usage":{"utilization":99}}
EOF
jq --argjson captured_at "$((NOW - 600))" '.captured_at = $captured_at' "$RATE_FILE" > "$RATE_FILE.tmp"
mv "$RATE_FILE.tmp" "$RATE_FILE"
: > "$NETWORK_LOG"
run_plugin "$NOW" claude click
assert_contains "$LOG_FILE" '--set claude_quota icon.color=0xffff9f1c label=90%' "fresher direct 5h reading must win over an older sidecar"
assert_contains "$LOG_FILE" '--set claude_quota_weekly icon.color=0xffff9f1c label=80%' "direct 7d reading must render"
assert_contains "$LOG_FILE" 'label=90% (1h 0m) | 80% (1d 0h) label.color=' "click detail must keep the compact format"
assert_contains "$NETWORK_LOG" 'https://api.anthropic.com/api/oauth/usage?cedar_ember=1' "Claude must use the OAuth usage endpoint"
assert_contains "$NETWORK_LOG" 'header = "anthropic-beta: oauth-2025-04-20"' "Claude must send the OAuth beta header"
assert_contains "$NETWORK_LOG" "header = \"Authorization: Bearer $CLAUDE_TOKEN\"" "token must travel through curl's stdin config"
assert_contains "$NETWORK_LOG" '--proto =https --max-redirs 0' "requests must be HTTPS-only without redirects"
if grep '^ARGS' "$NETWORK_LOG" | grep -Fq "$CLAUDE_TOKEN"; then
  fail "token must never appear in process arguments"
fi
if grep -rFq -e "$CLAUDE_TOKEN" "$CACHE"; then
  fail "token must never be cached"
fi
[ "$(stat -c '%a' "$CACHE/ai_quota_claude.json" 2>/dev/null || stat -f '%Lp' "$CACHE/ai_quota_claude.json")" = "600" ] || fail "snapshot mode must be 0600"
jq -e '.windows | keys == ["five_hour","seven_day"]' "$CACHE/ai_quota_claude.json" >/dev/null || fail "snapshot must keep only subscription windows"

# Interval gating: periodic ticks inside 5 minutes stay offline.
run_plugin "$((NOW + 60))" claude
[ "$(network_calls)" -eq 1 ] || fail "a periodic tick inside the interval must not fetch"
run_plugin "$((NOW + 301))" claude
[ "$(network_calls)" -eq 2 ] || fail "a periodic tick after the interval must fetch"

# 429 keeps the old reading with its age and backs off for 15 minutes.
printf 429 > "$FIXTURES/claude.code"
rm -f "$RATE_FILE" "$HOME/.claude.json"
run_plugin "$((NOW + 1300))" claude click
jq -e --argjson at "$((NOW + 301))" '.fetched_at == $at' "$CACHE/ai_quota_claude.json" >/dev/null || fail "a 429 must keep the previous snapshot"
jq -e '.status == "rate_limit"' "$CACHE/ai_quota_claude.fetch" >/dev/null || fail "a 429 must be recorded as rate_limit"
assert_contains "$LOG_FILE" 'label=90%~' "a 1000s-old reading must show the stale marker"
assert_contains "$LOG_FILE" '· rate limited' "stale detail must name the failed sync"
calls="$(network_calls)"
run_plugin "$((NOW + 1700))" claude
[ "$(network_calls)" -eq "$calls" ] || fail "periodic ticks must back off after a 429"
run_plugin "$((NOW + 5000))" claude
assert_contains "$LOG_FILE" 'label=90%!' "over-60-minute data must be marked old"
rm -f "$FIXTURES/claude.code"

# Expired token: reported as auth, no request.
printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":%s}}' "$CLAUDE_TOKEN" "$(((NOW + 6000) * 1000))" > "$FIXTURES/keychain.json"
calls="$(network_calls)"
run_plugin "$((NOW + 6000))" claude click
[ "$(network_calls)" -eq "$calls" ] || fail "an expired token must not be sent"
jq -e '.status == "auth"' "$CACHE/ai_quota_claude.fetch" >/dev/null || fail "an expired token must be recorded as auth"
assert_contains "$LOG_FILE" '· sign in again' "expired token detail must ask to sign in"

# No credentials: local sources still render.
rm -f "$FIXTURES/keychain.json"
cat > "$RATE_FILE" <<EOF
{"captured_at":$((NOW + 6100)),"five_hour":{"used_percentage":25,"resets_at":$((NOW + 9700))},"seven_day":{"used_percentage":40,"resets_at":$((NOW + 92500))}}
EOF
run_plugin "$((NOW + 6100))" claude click
jq -e '.status == "no_credentials"' "$CACHE/ai_quota_claude.fetch" >/dev/null || fail "missing credentials must be recorded"
assert_contains "$LOG_FILE" '--set claude_quota icon.color=0xffff9f1c label=75%' "local sidecar must remain the fallback"
assert_contains "$LOG_FILE" '--set claude_quota_weekly icon.color=0xffff9f1c label=60%' "local 7d fallback must render"
assert_contains "$LOG_FILE" 'label=75% (1h 0m) | 60% (1d 0h) label.color=0xffdbe9ff' "fresh local detail must stay compact and neutral"

# ── OpenAI: weekly-only reply collapses the box ─────────────────────────────
mkdir -p "$HOME/.codex"
printf '{"tokens":{"access_token":"%s","account_id":"acct-123"}}' "$CODEX_TOKEN" > "$HOME/.codex/auth.json"
cat > "$FIXTURES/openai.json" <<EOF
{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":604800,"reset_at":$((NOW + 86400))},"secondary_window":null}}
EOF
run_plugin "$NOW" openai click
assert_contains "$LOG_FILE" '--set openai_quota icon.color=0xffdbe9ff label=80%' "weekly-only OpenAI must fill the primary slot"
assert_contains "$LOG_FILE" '--set openai_quota_separator drawing=off --set openai_quota_weekly drawing=off' "weekly-only OpenAI must collapse to one panel"
assert_contains "$LOG_FILE" 'label=80% (1d 0h) label.color=0xffdbe9ff' "weekly-only detail must not report a missing 5h window"
assert_contains "$NETWORK_LOG" 'https://chatgpt.com/backend-api/wham/usage' "OpenAI must use the Codex usage endpoint"
assert_contains "$NETWORK_LOG" 'header = "ChatGPT-Account-Id: acct-123"' "OpenAI must scope the account"

cat > "$FIXTURES/openai.json" <<EOF
{"rate_limit":{"primary_window":{"used_percent":70,"limit_window_seconds":18000,"reset_at":$((NOW + 4000))},"secondary_window":{"used_percent":30,"limit_window_seconds":604800,"reset_at":$((NOW + 90000))}}}
EOF
run_plugin "$((NOW + 20))" openai click
assert_contains "$LOG_FILE" '--set openai_quota icon.color=0xffdbe9ff label=30% label.color=0xffffd23d' "OpenAI 5h must render with the warning color"
assert_contains "$LOG_FILE" '--set openai_quota_weekly icon.color=0xffdbe9ff label=70%' "OpenAI 7d must render"
assert_contains "$LOG_FILE" 'drawing=on' "both OpenAI windows must restore the split view"

# ── OpenCode Go: relative, ISO and millisecond resets ───────────────────────
mkdir -p "$HOME/.local/share/opencode"
printf '{"opencode-go":{"type":"api","key":"%s"}}' "$GO_KEY" > "$HOME/.local/share/opencode/auth.json"
cat > "$FIXTURES/opencode-go.json" <<EOF
{"usage":{"rolling":{"percent":10,"resetInSec":3600},"weekly":{"percent":20,"resetsAt":"2033-05-19T03:33:20.000Z"},"monthly":{"percent":30,"resetAt":$(((NOW + 172800) * 1000))}}}
EOF
run_plugin "$NOW" opencode-go click
assert_contains "$LOG_FILE" '--set opencode_quota icon.color=' "OpenCode Go primary must render"
assert_contains "$LOG_FILE" 'label=90% (1h 0m) | 80% (1d 0h) | 70% (2d 0h) label.color=' "OpenCode Go detail must include all three windows"
assert_contains "$NETWORK_LOG" "header = \"Authorization: Bearer $GO_KEY\"" "OpenCode Go must use its API key"

printf 'fail' > "$FIXTURES/opencode-go.code"
run_plugin "$((NOW + 4000))" opencode-go click
jq -e '.status == "network"' "$CACHE/ai_quota_opencode-go.fetch" >/dev/null || fail "a curl failure must be recorded as network"
jq -e --argjson at "$NOW" '.fetched_at == $at' "$CACHE/ai_quota_opencode-go.json" >/dev/null || fail "a network failure must keep the snapshot"
assert_contains "$LOG_FILE" '--set opencode_quota icon.color=0xffdbe9ff label=90%!' "a window whose reset passed must be marked old"
assert_contains "$LOG_FILE" '· offline' "failed detail must say offline"

printf 200 > "$FIXTURES/opencode-go.code"
printf 'not json' > "$FIXTURES/opencode-go.json"
run_plugin "$((NOW + 4100))" opencode-go click
jq -e '.status == "invalid"' "$CACHE/ai_quota_opencode-go.fetch" >/dev/null || fail "an unparsable reply must be recorded as invalid"
jq -e --argjson at "$NOW" '.fetched_at == $at' "$CACHE/ai_quota_opencode-go.json" >/dev/null || fail "an invalid reply must keep the snapshot"

# ── Copilot removed, one updater per provider ───────────────────────────────
run_plugin "$NOW" copilot
[ ! -s "$LOG_FILE" ] || fail "the removed copilot mode must not draw anything"
assert_not_contains "$CONFIG" 'copilot' "the Copilot panel must be gone"
if grep -rq 'opencode-quota' "$ROOT/sketchybar/plugins"; then
  fail "plugins must not depend on opencode-quota"
fi
for provider in claude openai opencode-go; do
  [ "$(grep -c "script=\"\$PLUGIN_DIR/ai_quota.sh $provider\"" "$CONFIG")" -eq 1 ] || fail "$provider must have exactly one periodic updater"
  if grep -q "script=\"\$PLUGIN_DIR/ai_quota.sh $provider weekly\"" "$CONFIG"; then
    fail "$provider weekly item must not schedule duplicate updates"
  fi
done

printf 'ok - AI quota direct fetch contracts\n'

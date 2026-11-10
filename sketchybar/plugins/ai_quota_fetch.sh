#!/bin/bash

# AI quota fetch - direct HTTPS usage reads (same method as QuotaShell)
#
# Usage: ai_quota_fetch.sh <openai|claude|opencode-go> [--force]
#
# One GET per provider usage endpoint with the credential its own CLI already
# stores locally. No redirects, no retries, no token renewal. A successful read
# replaces the normalized snapshot; any failure keeps the previous snapshot (and
# its original age) and only records the failure reason in the status file.
#
#   snapshot: $CACHE_DIR/ai_quota_<provider>.json
#     {"fetched_at":N,"windows":{"five_hour":{"used":P,"resets_at":E},"seven_day":{...},"monthly":{...}}}
#   status:   $CACHE_DIR/ai_quota_<provider>.fetch
#     {"attempted_at":N,"status":"ok|auth|permission|rate_limit|network|service|invalid|no_credentials"}

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$HOME/.nix-profile/bin"

PROVIDER="${1:-}"
FORCE=0
[ "${2:-}" = "--force" ] && FORCE=1

case "$PROVIDER" in
  openai|claude|opencode-go) ;;
  *)
    printf 'usage: %s <openai|claude|opencode-go> [--force]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac

JQ_BIN="$(command -v jq 2>/dev/null || true)"
CURL_BIN="$(command -v curl 2>/dev/null || true)"
[ -n "$JQ_BIN" ] && [ -n "$CURL_BIN" ] || exit 1

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
SNAPSHOT_FILE="$CACHE_DIR/ai_quota_${PROVIDER}.json"
STATUS_FILE="$CACHE_DIR/ai_quota_${PROVIDER}.fetch"
LOCK_DIR="$CACHE_DIR/ai_quota_${PROVIDER}.lock"
CODEX_AUTH="${AI_QUOTA_CODEX_AUTH:-${CODEX_HOME:-$HOME/.codex}/auth.json}"
OPENCODE_AUTH="${AI_QUOTA_OPENCODE_AUTH:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json}"
CLAUDE_CREDENTIALS_FILE="$HOME/.claude/.credentials.json"

# Periodic reads are spaced by INTERVAL; after a 429 by RATE_LIMIT_INTERVAL.
# A click (--force) only waits FORCE_INTERVAL, or a minute after a 429.
INTERVAL="${AI_QUOTA_INTERVAL:-300}"
RATE_LIMIT_INTERVAL=900
FORCE_INTERVAL=10
FORCE_RATE_LIMIT_INTERVAL=60

NOW="${AI_QUOTA_NOW:-$(date +%s)}"
case "$NOW" in
  ''|*[!0-9]*) NOW="$(date +%s)" ;;
esac

umask 077
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 1

atomic_write() {
  local target="$1" temp
  temp="$(mktemp "$target.XXXXXX")" || return 1
  if ! cat > "$temp"; then
    rm -f "$temp"
    return 1
  fi
  mv -f "$temp" "$target"
}

record_status() {
  "$JQ_BIN" -cn --argjson at "$NOW" --arg status "$1" '{attempted_at: $at, status: $status}' | atomic_write "$STATUS_FILE"
}

fetch_due() {
  local attempted status wait

  [ -f "$STATUS_FILE" ] || return 0
  attempted="$("$JQ_BIN" -r '.attempted_at // empty' "$STATUS_FILE" 2>/dev/null)"
  status="$("$JQ_BIN" -r '.status // empty' "$STATUS_FILE" 2>/dev/null)"
  case "$attempted" in
    ''|*[!0-9]*) return 0 ;;
  esac

  if [ "$FORCE" -eq 1 ]; then
    wait="$FORCE_INTERVAL"
    [ "$status" = "rate_limit" ] && wait="$FORCE_RATE_LIMIT_INTERVAL"
  else
    wait="$INTERVAL"
    [ "$status" = "rate_limit" ] && wait="$RATE_LIMIT_INTERVAL"
  fi
  # An attempt more than a day ahead means the clock moved back; refetch.
  [ $((NOW - attempted)) -ge "$wait" ] || [ "$attempted" -gt $((NOW + 86400)) ]
}

acquire_lock() {
  local age
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    return 0
  fi
  # A crashed fetch must not block forever: requests are bounded to ~25s.
  age=$(($(date +%s) - $(stat -f '%m' "$LOCK_DIR" 2>/dev/null || stat -c '%Y' "$LOCK_DIR" 2>/dev/null || date +%s)))
  if [ "$age" -gt 60 ]; then
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null && return 0
  fi
  return 1
}

# Credential values are printable ASCII without quotes or backslashes, so they
# are safe inside a curl config line and never need escaping.
valid_secret() {
  [ -n "$1" ] && [ "${#1}" -le 16384 ] || return 1
  case "$1" in
    *[\"\\]*|*$'\n'*) return 1 ;;
  esac
  printf '%s' "$1" | LC_ALL=C grep -Eq '^[[:graph:]]+$'
}

TOKEN=""
ACCOUNT_ID=""
URL=""
EXTRA_HEADER=""

load_credentials() {
  local raw expires

  case "$PROVIDER" in
    openai)
      [ -f "$CODEX_AUTH" ] || return 1
      TOKEN="$("$JQ_BIN" -r '.tokens.access_token // empty' "$CODEX_AUTH" 2>/dev/null)"
      ACCOUNT_ID="$("$JQ_BIN" -r '.tokens.account_id // empty' "$CODEX_AUTH" 2>/dev/null)"
      URL="https://chatgpt.com/backend-api/wham/usage"
      if [ -n "$ACCOUNT_ID" ]; then
        valid_secret "$ACCOUNT_ID" || return 1
        EXTRA_HEADER="ChatGPT-Account-Id: $ACCOUNT_ID"
      fi
      ;;
    claude)
      raw="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)"
      if [ -z "$raw" ] && [ -f "$CLAUDE_CREDENTIALS_FILE" ]; then
        raw="$(cat "$CLAUDE_CREDENTIALS_FILE" 2>/dev/null)"
      fi
      [ -n "$raw" ] || return 1
      TOKEN="$(printf '%s' "$raw" | "$JQ_BIN" -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)"
      expires="$(printf '%s' "$raw" | "$JQ_BIN" -r '.claudeAiOauth.expiresAt // empty | if type == "number" then floor else empty end' 2>/dev/null)"
      # Renewal belongs to Claude Code; an expired token is reported, not refreshed.
      if [ -n "$TOKEN" ] && [ -n "$expires" ] && [ "$expires" -le $((NOW * 1000)) ]; then
        TOKEN=""
        return 2
      fi
      URL="https://api.anthropic.com/api/oauth/usage?cedar_ember=1"
      EXTRA_HEADER="anthropic-beta: oauth-2025-04-20"
      ;;
    opencode-go)
      [ -f "$OPENCODE_AUTH" ] || return 1
      TOKEN="$("$JQ_BIN" -r '.["opencode-go"] | select(.type == "api") | .key // empty' "$OPENCODE_AUTH" 2>/dev/null)"
      URL="https://opencode.ai/zen/go/v1/usage"
      ;;
  esac

  valid_secret "$TOKEN"
}

# jq program turning one provider reply into the normalized windows object.
NORMALIZE_LIB='
def epoch:
  if type == "number" then (if . > 1000000000000 then (. / 1000) else . end | floor)
  elif type == "string" then
    ((capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$") // error("invalid date"))
      | (.d + "Z" | fromdateiso8601)
        - (if (.z // "Z") == "Z" then 0
           else (.z | capture("(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2})")
                 | ((.h | tonumber) * 3600 + (.m | tonumber) * 60) * (if .s == "+" then 1 else -1 end))
           end))
  else error("invalid date") end;
# A window the provider sends must be valid; a malformed one rejects the reply.
# Only an absent (null) window is skipped.
def present:
  if . == null then empty elif type == "object" then . else error("invalid window") end;
def window($used; $reset):
  if ($used | type) == "number" and $used >= 0 and $used <= 100
  then {used: $used, resets_at: ($reset | if . == null then null else epoch end)}
  else error("invalid window") end;
'

NORMALIZE_OPENAI='
[(.rate_limit.primary_window, .rate_limit.secondary_window) | present
  | ({"18000": "five_hour", "604800": "seven_day", "2592000": "monthly"}[(.limit_window_seconds // 0) | tostring]) as $key
  | select($key != null)
  | {key: $key, value: window(.used_percent; .reset_at)}]
| from_entries'

NORMALIZE_CLAUDE='
[{key: "five_hour", value: (.five_hour | present | window(.utilization; .resets_at))},
 {key: "seven_day", value: (.seven_day | present | window(.utilization; .resets_at))}]
| from_entries'

NORMALIZE_OPENCODE_GO='
def reset($now):
  (first(.resetInSec, .resetInSeconds, .resetSeconds, .reset_sec, .reset_in_sec, .resetsInSec, .resetsInSeconds, .resetIn, .resetSec | numbers) // null) as $relative
  | if $relative != null then $now + ($relative | floor)
    else first(.resetAt, .resetsAt, .reset_at, .resets_at, .nextReset, .next_reset, .renewAt, .renew_at | select(. != null)) // null
    end;
.usage as $usage
| [["rolling", "five_hour"], ["weekly", "seven_day"], ["monthly", "monthly"]]
| map(. as [$source, $key] | $usage[$source] | present | {key: $key, value: window(.percent; reset($now))})
| from_entries'

normalize_reply() {
  local program
  case "$PROVIDER" in
    openai) program="$NORMALIZE_OPENAI" ;;
    claude) program="$NORMALIZE_CLAUDE" ;;
    opencode-go) program="$NORMALIZE_OPENCODE_GO" ;;
  esac
  "$JQ_BIN" -ce --argjson now "$NOW" "$NORMALIZE_LIB $program | select(length > 0)" "$1" 2>/dev/null
}

http_status_name() {
  case "$1" in
    401) printf 'auth' ;;
    403) printf 'permission' ;;
    429) printf 'rate_limit' ;;
    000|'') printf 'network' ;;
    *) printf 'service' ;;
  esac
}

fetch_due || exit 0
acquire_lock || exit 0
BODY_FILE=""
# Recheck under the lock: a concurrent fetch may have just finished.
if ! fetch_due; then
  rmdir "$LOCK_DIR" 2>/dev/null
  exit 0
fi
trap 'rm -f "$BODY_FILE"; rmdir "$LOCK_DIR" 2>/dev/null' EXIT

load_credentials
case "$?" in
  0) ;;
  2) record_status auth; exit 1 ;;
  *) record_status no_credentials; exit 1 ;;
esac

BODY_FILE="$(mktemp "$CACHE_DIR/ai_quota_${PROVIDER}.body.XXXXXX")" || exit 1

# Secrets go through curl's stdin config, never through process arguments.
# --disable (must be first) ignores ~/.curlrc so no trace or retry can apply.
HTTP_CODE="$(
  {
    printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"
    [ -n "$EXTRA_HEADER" ] && printf 'header = "%s"\n' "$EXTRA_HEADER"
  } | "$CURL_BIN" --disable --config - --silent --retry 0 --proto '=https' --max-redirs 0 \
      --connect-timeout 10 --max-time 25 --max-filesize 262144 \
      --header 'Accept: application/json' --header 'User-Agent: QuotaShell/0.1' \
      --header 'Cache-Control: no-store' \
      --output "$BODY_FILE" --write-out '%{http_code}' "$URL" 2>/dev/null
)"
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ]; then
  record_status network
  exit 1
fi

case "$HTTP_CODE" in
  2??) ;;
  *)
    record_status "$(http_status_name "$HTTP_CODE")"
    exit 1
    ;;
esac

if ! WINDOWS="$(normalize_reply "$BODY_FILE")"; then
  record_status invalid
  exit 1
fi

"$JQ_BIN" -cn --argjson at "$NOW" --argjson windows "$WINDOWS" '{fetched_at: $at, windows: $windows}' | atomic_write "$SNAPSHOT_FILE" || exit 1
record_status ok

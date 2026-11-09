#!/bin/bash

# AI quota - provider quota labels from direct HTTPS usage reads
#
# ai_quota_fetch.sh reads each provider's usage endpoint (QuotaShell method) into
# a normalized snapshot; this script renders the remaining percentage of each
# window. Claude also keeps its local sources (status-line sidecar and Claude
# Code's own usage cache) and shows whichever reading is freshest.

# CONFIG_DIR is supplied by SketchyBar; resolve it for direct test/manual runs.
CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
source "$CONFIG_DIR/theme.sh"

YELLOW="$AI_WARNING"
RED="$AI_ERROR"
WHITE="$AI_TEXT"
ORANGE="$AI_CLAUDE"
OC_GO_ICON="$AI_OPENCODE"

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$HOME/.nix-profile/bin"

ACTION="auto"
for arg in "${@:2}"; do
  [ "$arg" = "click" ] && ACTION="click"
done

case "${1:-openai}" in
  openai)
    PROVIDER="openai"
    PRIMARY_ITEM="openai_quota"
    WEEKLY_ITEM="openai_quota_weekly"
    BOX_ITEM="openai_box"
    ICON_COLOR="$WHITE"
    ;;
  claude|anthropic)
    PROVIDER="claude"
    PRIMARY_ITEM="claude_quota"
    WEEKLY_ITEM="claude_quota_weekly"
    BOX_ITEM="claude_box"
    ICON_COLOR="$ORANGE"
    ;;
  opencode-go|opencodego|opencode_go)
    PROVIDER="opencode-go"
    PRIMARY_ITEM="opencode_quota"
    WEEKLY_ITEM="opencode_quota_weekly"
    BOX_ITEM="opencode_box"
    ICON_COLOR="$OC_GO_ICON"
    ;;
  *)
    exit 0
    ;;
esac

JQ_BIN="$(command -v jq 2>/dev/null || true)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
SNAPSHOT_FILE="$CACHE_DIR/ai_quota_${PROVIDER}.json"
STATUS_FILE="$CACHE_DIR/ai_quota_${PROVIDER}.fetch"
DETAIL_CACHE_FILE="$CACHE_DIR/ai_quota_${PROVIDER}.detail"
CLAUDE_RATE_LIMITS_FILE="$CACHE_DIR/claude-rate-limits.json"
CLAUDE_USAGE_FILE="$HOME/.claude.json"
# Global visibility toggle owned by ai_toggle.sh; layout logic must not re-draw.
HIDDEN_STATE_FILE="$CACHE_DIR/ai_quota_hidden"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# A reading is fresh under 15 minutes, stale ("~") up to an hour, then old ("!").
STALE_AGE=900
OLD_AGE=3600

atomic_write() {
  local target="$1"
  local value="$2"
  local temp

  (umask 077 && mkdir -p "$CACHE_DIR") 2>/dev/null || return
  temp="$(mktemp "$target.XXXXXX")" || return
  chmod 600 "$temp" 2>/dev/null || {
    rm -f "$temp"
    return
  }
  if ! printf '%s\n' "$value" > "$temp"; then
    rm -f "$temp"
    return
  fi
  mv -f "$temp" "$target"
}

query_item() {
  sketchybar --query "$1" 2>/dev/null | "$JQ_BIN" -r "$2 // empty" 2>/dev/null
}

set_detail_with_source_style() {
  local message="$1"
  local label_color="${2:-$WHITE}"
  local icon_value icon_color icon_font border_color

  icon_value="$(query_item "$PRIMARY_ITEM" '.icon.value')"
  icon_color="$(query_item "$PRIMARY_ITEM" '.icon.color')"
  icon_font="$(query_item "$PRIMARY_ITEM" '.icon.font')"
  border_color="$(query_item "$BOX_ITEM" '.geometry.background.border_color')"

  icon_color="${icon_color:-$WHITE}"
  icon_font="${icon_font:-IosevkaTerm NF:Bold:14.0}"
  border_color="${border_color:-$icon_color}"

  sketchybar --set ai_detail drawing=on icon.drawing=on icon="$icon_value" icon.color="$icon_color" icon.font="$icon_font" label="$message" label.color="$label_color" background.border_color="$border_color" >/dev/null 2>&1 || true
}

show_detail_box() {
  local message="$1"
  local label_color="$2"

  atomic_write "$DETAIL_CACHE_FILE" "$message" 2>/dev/null || true
  if [ "$ACTION" = "click" ]; then
    set_detail_with_source_style "$message" "$label_color"
    "$SCRIPT_DIR/ai_detail_clear.sh" >/dev/null 2>&1 &
  fi
}

fmt_reset_remaining() {
  local reset_at="$1"
  local diff days hours mins

  case "$reset_at" in
    ''|*[!0-9]*)
      printf -- "--"
      return
      ;;
  esac

  diff=$((reset_at - NOW))
  if [ "$diff" -le 0 ]; then
    printf -- "now"
    return
  fi

  days=$((diff / 86400))
  hours=$(((diff % 86400) / 3600))
  mins=$(((diff % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf -- "%dd %dh" "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf -- "%dh %dm" "$hours" "$mins"
  else
    printf -- "%dm" "$mins"
  fi
}

pick_color_by_pct() {
  local pct="$1"
  if [ "$pct" -lt 20 ]; then
    printf -- "%s" "$RED"
  elif [ "$pct" -lt 40 ]; then
    printf -- "%s" "$YELLOW"
  else
    printf -- "%s" "$WHITE"
  fi
}

parse_reset_epoch() {
  printf '%s' "$1" | "$JQ_BIN" -Rr '
    if test("^[0-9]+$") then .
    else capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(Z|[+]00:?00)?$")
      | .d + "Z" | fromdateiso8601 | tostring end' 2>/dev/null
}

valid_percentage() {
  printf '%s' "$1" | "$JQ_BIN" -eR 'tonumber | isfinite and . >= 0 and . <= 100' >/dev/null 2>&1
}

valid_epoch() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ] && [ "$1" -le 32503680000 ]
}

# Loads one window from one source into CANDIDATE_* (remaining %, reset, age).
load_candidate() {
  local kind="$1" window="$2"
  local file captured used reset legacy_window

  case "$kind" in
    direct)
      file="$SNAPSHOT_FILE"
      [ -f "$file" ] || return 1
      captured="$("$JQ_BIN" -r '.fetched_at // empty' "$file" 2>/dev/null)"
      used="$("$JQ_BIN" -r --arg window "$window" '.windows[$window].used // empty' "$file" 2>/dev/null)"
      reset="$("$JQ_BIN" -r --arg window "$window" '.windows[$window].resets_at // empty' "$file" 2>/dev/null)"
      ;;
    status-line)
      file="$CLAUDE_RATE_LIMITS_FILE"
      [ -f "$file" ] || return 1
      captured="$("$JQ_BIN" -r '.captured_at // empty' "$file" 2>/dev/null)"
      used="$("$JQ_BIN" -r --arg window "$window" '.[$window].used_percentage // empty' "$file" 2>/dev/null)"
      reset="$("$JQ_BIN" -r --arg window "$window" '.[$window].resets_at // empty' "$file" 2>/dev/null)"
      ;;
    claude-cache)
      file="$CLAUDE_USAGE_FILE"
      [ -f "$file" ] || return 1
      captured="$("$JQ_BIN" -r '.cachedUsageUtilization.fetchedAtMs // empty | if type == "number" then (floor / 1000 | floor) else empty end' "$file" 2>/dev/null)"
      used="$("$JQ_BIN" -r --arg window "$window" '.cachedUsageUtilization.utilization[$window].utilization // empty' "$file" 2>/dev/null)"
      reset="$("$JQ_BIN" -r --arg window "$window" '.cachedUsageUtilization.utilization[$window].resets_at // empty' "$file" 2>/dev/null)"
      reset="$(parse_reset_epoch "$reset")"
      ;;
    widget-cache)
      # Last rendered label; value only, always shown as old.
      [ "$window" = "five_hour" ] && legacy_window=primary || legacy_window=weekly
      file="$CACHE_DIR/ai_quota_${PROVIDER}_${legacy_window}.state"
      [ -f "$file" ] || return 1
      used="$(cut -d '|' -f 2- "$file" 2>/dev/null)"
      used="${used%!}"
      used="${used%~}"
      used="${used%%%}"
      case "$used" in
        ''|*[!0-9]*) return 1 ;;
      esac
      [ "$used" -le 100 ] || return 1
      CANDIDATE_REMAINING="$used"
      CANDIDATE_RESET=""
      CANDIDATE_AGE=$((OLD_AGE + 1))
      return 0
      ;;
  esac

  valid_percentage "$used" || return 1
  valid_epoch "$captured" || return 1
  [ "$captured" -le $((NOW + 300)) ] || return 1
  if [ -n "$reset" ]; then
    valid_epoch "$reset" || return 1
  fi

  CANDIDATE_REMAINING="$(printf '%s' "$used" | awk '{ printf "%d", 100 - $1 }')"
  CANDIDATE_RESET="$reset"
  CANDIDATE_AGE=$((NOW - captured))
  [ "$CANDIDATE_AGE" -ge 0 ] || CANDIDATE_AGE=0
  return 0
}

# Prints "remaining|reset|age|state" with the freshest usable reading of a window.
# state: fresh | stale | old | missing. A reading whose reset already passed is old.
select_window() {
  local window="$1"
  local kind sources best="" best_age="" fallback="" state

  sources="direct"
  [ "$PROVIDER" = "claude" ] && sources="direct status-line claude-cache"

  for kind in $sources; do
    load_candidate "$kind" "$window" || continue
    if [ -n "$CANDIDATE_RESET" ] && [ "$CANDIDATE_RESET" -le "$NOW" ]; then
      [ -n "$fallback" ] || fallback="$CANDIDATE_REMAINING|$CANDIDATE_RESET|$CANDIDATE_AGE|old"
      continue
    fi
    if [ -z "$best_age" ] || [ "$CANDIDATE_AGE" -lt "$best_age" ]; then
      best="$CANDIDATE_REMAINING|$CANDIDATE_RESET|$CANDIDATE_AGE"
      best_age="$CANDIDATE_AGE"
    fi
  done

  if [ -n "$best" ]; then
    if [ "$best_age" -gt "$OLD_AGE" ]; then
      state=old
    elif [ "$best_age" -ge "$STALE_AGE" ]; then
      state=stale
    else
      state=fresh
    fi
    printf '%s|%s' "$best" "$state"
  elif [ -n "$fallback" ]; then
    printf '%s' "$fallback"
  elif load_candidate widget-cache "$window"; then
    printf '%s||%s|old' "$CANDIDATE_REMAINING" "$CANDIDATE_AGE"
  else
    printf '|||missing'
  fi
}

render_window() {
  local item="$1" window="$2" result="$3"
  local value reset age state marker="" color label legacy_window
  IFS='|' read -r value reset age state <<< "$result"

  if [ -z "$value" ]; then
    sketchybar --set "$item" icon.color="$ICON_COLOR" label="--!" label.color="$YELLOW" >/dev/null 2>&1 || true
    return
  fi

  color="$(pick_color_by_pct "$value")"
  case "$state" in
    stale) marker="~" ; color="$YELLOW" ;;
    old) marker="!" ; color="$YELLOW" ;;
  esac
  label="${value}%${marker}"

  if [ "$state" != "old" ]; then
    [ "$window" = "five_hour" ] && legacy_window=primary || legacy_window=weekly
    atomic_write "$CACHE_DIR/ai_quota_${PROVIDER}_${legacy_window}.state" "$ICON_COLOR|${value}%" 2>/dev/null || true
  fi
  sketchybar --set "$item" icon.color="$ICON_COLOR" label="$label" label.color="$color" >/dev/null 2>&1 || true
}

detail_window() {
  local value reset age state
  IFS='|' read -r value reset age state <<< "$1"
  if [ -z "$value" ]; then
    printf 'unavailable'
    return
  fi
  printf '%s%% (%s)' "$value" "$(fmt_reset_remaining "$reset")"
}

fetch_failure_reason() {
  local status
  status="$("$JQ_BIN" -r '.status // empty' "$STATUS_FILE" 2>/dev/null)"
  case "$status" in
    auth) printf 'sign in again' ;;
    permission) printf 'access denied' ;;
    rate_limit) printf 'rate limited' ;;
    network) printf 'offline' ;;
    service) printf 'service error' ;;
    invalid) printf 'invalid reply' ;;
    no_credentials) printf 'not signed in' ;;
  esac
}

# OpenAI (Plus) currently reports only a weekly window. Without a 5h value the
# box collapses to a single weekly panel; the split returns when 5h comes back.
apply_openai_split_layout() {
  local drawing="$1"
  [ -f "$HIDDEN_STATE_FILE" ] && return
  sketchybar --set openai_quota_separator drawing="$drawing" \
             --set openai_quota_weekly drawing="$drawing" >/dev/null 2>&1 || true
}

NOW="${AI_QUOTA_NOW:-$(date +%s)}"
case "$NOW" in
  ''|*[!0-9]*) NOW="$(date +%s)" ;;
esac

if [ -z "$JQ_BIN" ]; then
  sketchybar --set "$PRIMARY_ITEM" label="--" --set "$WEEKLY_ITEM" label="--" >/dev/null 2>&1 || true
  exit 0
fi

if [ "$ACTION" = "click" ]; then
  sketchybar --set "$PRIMARY_ITEM" label.color="$YELLOW" >/dev/null 2>&1 || true
  "$SCRIPT_DIR/ai_quota_fetch.sh" "$PROVIDER" --force >/dev/null 2>&1
else
  # The fetcher spaces its own requests; most ticks return without network.
  "$SCRIPT_DIR/ai_quota_fetch.sh" "$PROVIDER" >/dev/null 2>&1
fi

FIVE_HOUR="$(select_window five_hour)"
SEVEN_DAY="$(select_window seven_day)"

primary="$FIVE_HOUR"
weekly_drawing=on
if [ "$PROVIDER" = "openai" ] && [[ "$FIVE_HOUR" == *'|missing' ]] && [[ "$SEVEN_DAY" != *'|missing' ]]; then
  primary="$SEVEN_DAY"
  weekly_drawing=off
fi

render_window "$PRIMARY_ITEM" "$( [ "$primary" = "$FIVE_HOUR" ] && printf five_hour || printf seven_day )" "$primary"
render_window "$WEEKLY_ITEM" seven_day "$SEVEN_DAY"
[ "$PROVIDER" = "openai" ] && apply_openai_split_layout "$weekly_drawing"

if [[ "$FIVE_HOUR" == *'|missing' && "$SEVEN_DAY" == *'|missing' ]]; then
  detail="quota unavailable"
elif [ "$weekly_drawing" = "off" ]; then
  detail="$(detail_window "$SEVEN_DAY")"
else
  detail="$(detail_window "$FIVE_HOUR") | $(detail_window "$SEVEN_DAY")"
fi
if [ "$PROVIDER" = "opencode-go" ]; then
  MONTHLY="$(select_window monthly)"
  [[ "$MONTHLY" == *'|missing' ]] || detail="$detail | $(detail_window "$MONTHLY")"
fi

detail_color="$WHITE"
shown="$FIVE_HOUR $SEVEN_DAY"
[ "$weekly_drawing" = "off" ] && shown="$SEVEN_DAY"
if [[ "$shown" == *'|stale'* || "$shown" == *'|old'* || "$shown" == *'|missing'* ]]; then
  reason="$(fetch_failure_reason)"
  [ -n "$reason" ] && detail="$detail · $reason"
  detail_color="$YELLOW"
fi
show_detail_box "$detail" "$detail_color"

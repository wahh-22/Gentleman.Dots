#!/usr/bin/env bash

set -euo pipefail

REPO=${1:-"$(cd "$(dirname "$0")/../.." && pwd)"}
PROFILE="$REPO/herdr/profiles/gentleman-blue.toml"
SELECTOR="$REPO/herdr/herdr-theme"
NIX_FILE="$REPO/herdr.nix"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/herdr-theme-tests.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT

HOME_DIR="$TEMP_ROOT/home"
CONFIG_DIR="$HOME_DIR/.config/herdr"
BIN_DIR="$TEMP_ROOT/bin"
HERDR_LOG="$TEMP_ROOT/herdr.log"

fail() {
  printf 'assertion failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local path=$1
  local expected=$2
  local message=$3
  grep -Fq -- "$expected" "$path" || fail "$message"
}

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3

  if [ "$expected" != "$actual" ]; then
    printf 'assertion failed: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_active_profile() {
  local theme=$1
  local expected="$TEMP_ROOT/expected-$theme.toml"
  cat "$CONFIG_DIR/config-base.toml" "$CONFIG_DIR/profiles/$theme.toml" > "$expected"
  cmp -s "$expected" "$CONFIG_DIR/config.toml" || fail "$theme must assemble the base config and selected profile"
  [ -w "$CONFIG_DIR/config.toml" ] || fail "$theme must leave the active config writable"
}

[ -r "$PROFILE" ] || fail 'Gentleman Blue Herdr profile must exist'
[ -x "$SELECTOR" ] || fail 'The repository Herdr selector must be executable'
assert_contains "$PROFILE" 'panel_bg = "#05070F"' 'Herdr uses the Night City background'
assert_contains "$PROFILE" 'accent = "#347AFF"' 'Herdr uses electric blue as its accent'
assert_contains "$PROFILE" 'text = "#DBE9FF"' 'Herdr uses the Night City foreground'
assert_contains "$PROFILE" 'green = "#4DFF88"' 'Herdr preserves semantic success green'
assert_contains "$PROFILE" 'red = "#FF6B7A"' 'Herdr preserves semantic error red'
assert_contains "$PROFILE" 'sidebar_bg = "#070B1A"' 'Herdr sidebar uses the Night City surface, not One Dark'
assert_contains "$PROFILE" 'active_row_bg = "#10182E"' 'Herdr active row uses the Pi user-message surface'
assert_contains "$PROFILE" 'selection_bg = "#1C2C54"' 'Herdr selection matches Pi selectedBg'

mkdir -p "$CONFIG_DIR/profiles" "$BIN_DIR"
cp "$REPO/herdr/config-base.toml" "$CONFIG_DIR/config-base.toml"
cp "$REPO/herdr/profiles/gentleman.toml" "$CONFIG_DIR/profiles/gentleman.toml"
cp "$REPO/herdr/profiles/gentleman-cute.toml" "$CONFIG_DIR/profiles/gentleman-cute.toml"
cp "$REPO/herdr/profiles/gentleman-blue.toml" "$CONFIG_DIR/profiles/gentleman-blue.toml"

cat > "$BIN_DIR/herdr" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$HERDR_LOG"
STUB
chmod +x "$BIN_DIR/herdr"

# The actual selector assembles each supported profile and reloads Herdr.
for theme in gentleman gentleman-cute gentleman-blue; do
  HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" HERDR_LOG="$HERDR_LOG" "$SELECTOR" "$theme" >/dev/null
  assert_active_profile "$theme"
done
assert_eq $'server reload-config\nserver reload-config\nserver reload-config' "$(cat "$HERDR_LOG")" 'Every runtime selection reloads Herdr'

# Invalid input fails without replacing the active config.
cp "$CONFIG_DIR/config.toml" "$TEMP_ROOT/config-before-invalid.toml"
set +e
HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" HERDR_LOG="$HERDR_LOG" "$SELECTOR" unknown >/dev/null 2>&1
selector_status=$?
set -e
assert_eq '2' "$selector_status" 'Unknown Herdr themes are rejected'
cmp -s "$TEMP_ROOT/config-before-invalid.toml" "$CONFIG_DIR/config.toml" || fail 'Invalid input must preserve the active Herdr config'

# Installation defaults to Gentleman Blue only for a fresh config.
rm -f "$CONFIG_DIR/config.toml"
HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" "$SELECTOR" --install-default >/dev/null
assert_active_profile gentleman-blue
printf 'personalized = true\n' > "$CONFIG_DIR/config.toml"
HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" "$SELECTOR" --install-default >/dev/null
assert_eq 'personalized = true' "$(cat "$CONFIG_DIR/config.toml")" 'Installation preserves an existing Herdr config'

# Nix evaluates the installed command to the same repository script exercised above.
installed_selector=$(nix-instantiate --eval --strict --json --expr "
  let
    module = import $NIX_FILE;
    config = module {
      lib.hm.dag.entryAfter = _: value: value;
    };
  in toString config.home.file.\".local/bin/herdr-theme\".source
" | sed 's/^"//; s/"$//')
assert_eq "$SELECTOR" "$installed_selector" 'Home Manager installs the tested Herdr selector verbatim'

printf 'Herdr theme profile tests passed\n'

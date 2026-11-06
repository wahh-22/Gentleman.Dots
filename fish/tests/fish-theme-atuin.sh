#!/usr/bin/env bash

set -euo pipefail

REPO=${1:-"$(cd "$(dirname "$0")/../.." && pwd)"}
FUNCTION="$REPO/fish/functions/fish-theme.fish"
STARTUP_FUNCTION="$REPO/fish/functions/gentleman-theme-init.fish"
FISH_BIN=$(command -v fish)
TEMP_BASE=${TMPDIR:-/tmp}
TEMP_ROOT=$(mktemp -d "${TEMP_BASE%/}/fish-theme-atuin-tests.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT

HOME_DIR="$TEMP_ROOT/home"
CONFIG_DIR="$HOME_DIR/.config"
BIN_DIR="$TEMP_ROOT/bin"
ATUIN_LOG="$TEMP_ROOT/atuin.log"
STARSHIP_STATE="$TEMP_ROOT/starship-state"

mkdir -p "$CONFIG_DIR/fish/themes" "$CONFIG_DIR/starship" "$CONFIG_DIR/atuin/themes" "$BIN_DIR"
cp "$REPO/fish/themes/gentleman.fish" "$CONFIG_DIR/fish/themes/gentleman.fish"
cp "$REPO/fish/themes/gentleman-cute.fish" "$CONFIG_DIR/fish/themes/gentleman-cute.fish"
cp "$REPO/fish/themes/gentleman-blue.fish" "$CONFIG_DIR/fish/themes/gentleman-blue.fish"
printf '# Starship profile fixture\n' > "$CONFIG_DIR/starship/gentleman.toml"
printf '# Starship profile fixture\n' > "$CONFIG_DIR/starship/gentleman-cute.toml"
printf '# Starship profile fixture\n' > "$CONFIG_DIR/starship/gentleman-blue.toml"
printf '[theme]\n[colors]\n' > "$CONFIG_DIR/atuin/themes/gentleman.toml"
printf '[theme]\n[colors]\n' > "$CONFIG_DIR/atuin/themes/gentleman-cute.toml"
printf '[theme]\n[colors]\n' > "$CONFIG_DIR/atuin/themes/gentleman-blue.toml"
cat > "$CONFIG_DIR/atuin/config.toml" <<'CONFIG'
enter_accept = true

[sync]
records = true
CONFIG

cat > "$BIN_DIR/fish" <<EOF
#!/usr/bin/env bash
exec "$FISH_BIN" "\$@"
EOF
chmod +x "$BIN_DIR/fish"

cat > "$BIN_DIR/atuin" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$ATUIN_LOG"
if [ "${ATUIN_STUB_EXIT:-0}" != '0' ]; then
  exit "$ATUIN_STUB_EXIT"
fi

if [ "$1" = config ] && [ "$2" = set ] && [ "$3" = theme.name ]; then
  config="$HOME/.config/atuin/config.toml"
  temporary="$config.tmp"
  awk -v name="$4" '
    BEGIN { in_theme = 0; found_theme = 0 }
    /^\[theme\]$/ { in_theme = 1; found_theme = 1; print; next }
    /^\[/ { in_theme = 0 }
    in_theme && /^name[[:space:]]*=/ { print "name = \"" name "\""; next }
    { print }
    END {
      if (!found_theme) {
        print ""
        print "[theme]"
        print "name = \"" name "\""
      }
    }
  ' "$config" > "$temporary"
  mv "$temporary" "$config"
fi
STUB
chmod +x "$BIN_DIR/atuin"

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3

  if [ "$expected" != "$actual" ]; then
    printf 'assertion failed: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_file_contains() {
  local path=$1
  local expected=$2
  local message=$3

  if ! grep -Fq -- "$expected" "$path"; then
    printf 'assertion failed: %s\nmissing: %s\n' "$message" "$expected" >&2
    exit 1
  fi
}

assert_no_candidates() {
  if find "$CONFIG_DIR/fish" -maxdepth 1 -name '.gentleman-theme.*' -print -quit | grep -q .; then
    printf 'assertion failed: Fish selector candidate was not cleaned up\n' >&2
    exit 1
  fi
}

run_selector() {
  # Fish expands $argv inside the child process, not in this Bash test.
  # shellcheck disable=SC2016
  HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" ATUIN_LOG="$ATUIN_LOG" ATUIN_STUB_EXIT="${ATUIN_STUB_EXIT:-0}" STARSHIP_STATE="$STARSHIP_STATE" "$FISH_BIN" -c 'source "$argv[1]"; fish-theme "$argv[2]"; set -l selector_status $status; if test $selector_status -eq 0; printf "%s\n" "$STARSHIP_CONFIG" > "$STARSHIP_STATE"; end; exit $selector_status' "$FUNCTION" "$1"
}

run_startup_selection() {
  # Print the state produced by the same startup function Home Manager invokes.
  # shellcheck disable=SC2016
  HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" "$FISH_BIN" -c 'source "$argv[1]"; gentleman-theme-init; and printf "%s\n%s\n%s\n" "$gentleman_active_theme" "$STARSHIP_CONFIG" "$fish_color_normal"' "$STARTUP_FUNCTION"
}

# Managed assets use Atuin's complete 18.15.2 foreground-only theme schema and approved palettes.
assert_eq "$(cat <<'THEME'
[theme]
name = "gentleman"
parent = "default"

[colors]
AlertInfo = "#7FB4CA"
AlertWarn = "#FFE066"
AlertError = "#CB7C94"
Annotation = "#DEBA87"
Base = "#F3F6F9"
Guidance = "#7AA89F"
Important = "#FF8DD7"
Title = "#FF8DD7"
Muted = "#8394A3"
THEME
)" "$(cat "$REPO/atuin/themes/gentleman.toml")" 'Gentleman declares exact Atuin metadata and foreground semantic palette'

assert_eq "$(cat <<'THEME'
[theme]
name = "gentleman-cute"
parent = "default"

[colors]
AlertInfo = "#A9C7EE"
AlertWarn = "#F2B86D"
AlertError = "#FF718F"
Annotation = "#A78E9B"
Base = "#F6EFF3"
Guidance = "#B4E7C7"
Important = "#F095C8"
Title = "#FFB1DD"
Muted = "#76616B"
THEME
)" "$(cat "$REPO/atuin/themes/gentleman-cute.toml")" 'Cute declares exact Atuin metadata and foreground semantic palette'

assert_eq "$(cat <<'THEME'
[theme]
name = "gentleman-blue"
parent = "default"

[colors]
AlertInfo = "#5CE1FF"
AlertWarn = "#FFD23D"
AlertError = "#FF6B7A"
Annotation = "#FF9F1C"
Base = "#DBE9FF"
Guidance = "#4DFF88"
Important = "#7C5CFF"
Title = "#347AFF"
Muted = "#4A5578"
THEME
)" "$(cat "$REPO/atuin/themes/gentleman-blue.toml")" 'Gentleman Blue declares the Night City Atuin semantic palette'

# Evaluate Fish's Home Manager output with bounded stubs. The comparison verifies
# every resolved target, source path, and installed byte before checking startup behavior.
fish_wiring=$(nix-instantiate --eval --strict --json --expr "
  let
    module = import $REPO/fish.nix;
    config = module { pkgs = {}; };
    expectedFiles = [
      { target = \".config/fish/functions/fish-theme.fish\"; source = $REPO/fish/functions/fish-theme.fish; }
      { target = \".config/fish/functions/gentleman-theme-init.fish\"; source = $REPO/fish/functions/gentleman-theme-init.fish; }
      { target = \".config/fish/themes/gentleman.fish\"; source = $REPO/fish/themes/gentleman.fish; }
      { target = \".config/fish/themes/gentleman-cute.fish\"; source = $REPO/fish/themes/gentleman-cute.fish; }
      { target = \".config/fish/themes/gentleman-blue.fish\"; source = $REPO/fish/themes/gentleman-blue.fish; }
      { target = \".config/atuin/themes/gentleman.toml\"; source = $REPO/atuin/themes/gentleman.toml; }
      { target = \".config/atuin/themes/gentleman-cute.toml\"; source = $REPO/atuin/themes/gentleman-cute.toml; }
      { target = \".config/atuin/themes/gentleman-blue.toml\"; source = $REPO/atuin/themes/gentleman-blue.toml; }
    ];
    resolveExpected = file: {
      inherit (file) target;
      source = toString file.source;
      content = builtins.readFile file.source;
    };
    resolveActual = file: let
      source = config.home.file.\${file.target}.source;
    in {
      inherit (file) target;
      source = toString source;
      content = builtins.readFile source;
    };
    expected = map resolveExpected expectedFiles;
    actual = map resolveActual expectedFiles;
    contains = needle: haystack: let
      needleLength = builtins.stringLength needle;
      haystackLength = builtins.stringLength haystack;
      scan = offset:
        offset + needleLength <= haystackLength
        && (builtins.substring offset needleLength haystack == needle || scan (offset + 1));
    in needleLength == 0 || scan 0;
    startup = config.programs.fish.interactiveShellInit;
    startupFunction = builtins.readFile config.home.file.\".config/fish/functions/gentleman-theme-init.fish\".source;
  in
    assert actual == expected;
    assert contains \"gentleman-theme-init\\n\" startup;
    assert contains \"set -l active_theme gentleman-blue\" startupFunction;
    {
      defaultTheme = \"gentleman-blue\";
      startupInvokesInit = true;
      validatedTargets = map (file: file.target) actual;
    }
")
assert_eq '{"defaultTheme":"gentleman-blue","startupInvokesInit":true,"validatedTargets":[".config/fish/functions/fish-theme.fish",".config/fish/functions/gentleman-theme-init.fish",".config/fish/themes/gentleman.fish",".config/fish/themes/gentleman-cute.fish",".config/fish/themes/gentleman-blue.fish",".config/atuin/themes/gentleman.toml",".config/atuin/themes/gentleman-cute.toml",".config/atuin/themes/gentleman-blue.toml"]}' "$fish_wiring" 'Evaluated Fish wiring installs exact assets and starts with Gentleman Blue'

# Evaluate Starship's Home Manager output rather than grepping its Nix source.
starship_wiring=$(nix-instantiate --eval --strict --json --expr "
  let
    module = import $REPO/starship.nix;
    config = module {
      pkgs.formats.toml = _: {
        generate = name: _: name;
      };
    };
  in {
    default = config.home.file.\".config/starship.toml\".source;
    blue = config.home.file.\".config/starship/gentleman-blue.toml\".source;
  }
")
assert_eq '{"blue":"starship-gentleman-blue.toml","default":"starship-gentleman-blue.toml"}' "$starship_wiring" 'Evaluated Starship wiring uses Gentleman Blue for the default and named profile'

# Execute Fish's startup selection contract with an isolated HOME.
startup_state=$(run_startup_selection)
assert_eq "gentleman-blue
$CONFIG_DIR/starship/gentleman-blue.toml
#DBE9FF" "$startup_state" 'Fish startup defaults to Gentleman Blue and exports its Starship profile'
printf 'gentleman-cute\n' > "$CONFIG_DIR/fish/gentleman-theme"
startup_state=$(run_startup_selection)
assert_eq "gentleman-cute
$CONFIG_DIR/starship/gentleman-cute.toml
#F6EFF3" "$startup_state" 'Fish startup applies a persisted supported theme and matching Starship profile'
printf 'unsupported\n' > "$CONFIG_DIR/fish/gentleman-theme"
startup_state=$(run_startup_selection)
assert_eq "gentleman-blue
$CONFIG_DIR/starship/gentleman-blue.toml
#DBE9FF" "$startup_state" 'Fish startup ignores an unsupported marker and retains the Gentleman Blue default'

# Every supported profile invokes Atuin's config setter and publishes the shared marker.
: > "$ATUIN_LOG"
run_selector gentleman-blue
assert_eq 'gentleman-blue' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Gentleman Blue publishes the Fish marker'
assert_file_contains "$ATUIN_LOG" 'config set theme.name gentleman-blue' 'Gentleman Blue persists the matching Atuin profile'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'name = "gentleman-blue"' 'Gentleman Blue activates the matching Atuin theme'
assert_eq "$CONFIG_DIR/starship/gentleman-blue.toml" "$(cat "$STARSHIP_STATE")" 'Gentleman Blue exports the matching Starship profile'
assert_no_candidates

run_selector gentleman
assert_eq 'gentleman' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Gentleman publishes the Fish marker'
assert_file_contains "$ATUIN_LOG" 'config set theme.name gentleman' 'Gentleman persists the Atuin profile'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'enter_accept = true' 'Gentleman retains unrelated Atuin config'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'records = true' 'Gentleman retains Atuin sync configuration'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'name = "gentleman"' 'Gentleman activates the matching Atuin theme'
assert_eq "$CONFIG_DIR/starship/gentleman.toml" "$(cat "$STARSHIP_STATE")" 'Gentleman exports the matching Starship profile'
assert_no_candidates

run_selector gentleman-cute
assert_eq 'gentleman-cute' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Cute publishes the Fish marker'
assert_file_contains "$ATUIN_LOG" 'config set theme.name gentleman-cute' 'Cute persists the Atuin profile'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'enter_accept = true' 'Cute retains unrelated Atuin config'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'records = true' 'Cute retains Atuin sync configuration'
assert_file_contains "$CONFIG_DIR/atuin/config.toml" 'name = "gentleman-cute"' 'Cute activates the matching Atuin theme'
assert_eq "$CONFIG_DIR/starship/gentleman-cute.toml" "$(cat "$STARSHIP_STATE")" 'Cute exports the matching Starship profile'
assert_no_candidates

# A missing selected theme is rejected before either Atuin or the Fish marker changes.
printf 'gentleman\n' > "$CONFIG_DIR/fish/gentleman-theme"
mv "$CONFIG_DIR/atuin/themes/gentleman-cute.toml" "$CONFIG_DIR/atuin/themes/gentleman-cute.toml.unavailable"
: > "$ATUIN_LOG"
set +e
run_selector gentleman-cute >/dev/null 2>&1
selector_status=$?
set -e
assert_eq '1' "$selector_status" 'Missing Atuin theme exits with failure'
assert_eq 'gentleman' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Missing Atuin theme retains the previous Fish marker'
assert_eq '' "$(cat "$ATUIN_LOG")" 'Missing Atuin theme does not invoke Atuin'
assert_no_candidates
mv "$CONFIG_DIR/atuin/themes/gentleman-cute.toml.unavailable" "$CONFIG_DIR/atuin/themes/gentleman-cute.toml"

# A missing Atuin executable is rejected before the Fish marker changes.
printf 'gentleman\n' > "$CONFIG_DIR/fish/gentleman-theme"
mv "$BIN_DIR/atuin" "$BIN_DIR/atuin.unavailable"
set +e
run_selector gentleman-cute >/dev/null 2>&1
selector_status=$?
set -e
assert_eq '1' "$selector_status" 'Missing Atuin executable exits with failure'
assert_eq 'gentleman' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Missing Atuin executable retains the previous Fish marker'
assert_no_candidates
mv "$BIN_DIR/atuin.unavailable" "$BIN_DIR/atuin"

# A failed Atuin update does not report success or claim a fully applied Fish profile.
printf 'gentleman\n' > "$CONFIG_DIR/fish/gentleman-theme"
: > "$ATUIN_LOG"
set +e
ATUIN_STUB_EXIT=23 run_selector gentleman-cute >/dev/null 2>&1
selector_status=$?
set -e
assert_eq '23' "$selector_status" 'Failed Atuin update returns Atuin failure'
assert_eq 'gentleman' "$(cat "$CONFIG_DIR/fish/gentleman-theme")" 'Failed Atuin update retains the previous Fish marker'
assert_file_contains "$ATUIN_LOG" 'config set theme.name gentleman-cute' 'Failed update attempted the selected Atuin profile'
assert_no_candidates

printf 'fish theme Atuin tests passed\n'

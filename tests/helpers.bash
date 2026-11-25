# Shared test helpers. Every test runs in a throwaway HOME with a fake `claude`
# on PATH, so nothing touches the real ~/.claude, ~/.claude.json or Keychain.
#
# TEST_BASH picks the interpreter the script runs under (CI also runs the
# suite with macOS's /bin/bash 3.2).

setup_isolated_env() {
  # The space in the name makes every test run with a HOME containing a space.
  TESTTMP="$(mktemp -d "${TMPDIR:-/tmp}/claude as test.XXXXXX")"
  # Resolve /var -> /private/var on macOS so path comparisons are exact.
  TESTTMP="$(cd "$TESTTMP" && pwd -P)"
  export TESTTMP
  export HOME="$TESTTMP/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  SCRIPT="$BATS_TEST_DIRNAME/../bin/claude-as"
  SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd -P)/claude-as"
  export SCRIPT
  TEST_BASH="${TEST_BASH:-bash}"
  export TEST_BASH

  unset CLAUDE_CONFIG_DIR CLAUDE_AS_PROFILE CLAUDE_AS_BIN CLAUDE_AS_BASE CLAUDE_AS_CONFIG CLAUDE_AS_JQ

  mkdir -p "$HOME/.claude/skills/my-skill" "$TESTTMP/fakebin"
  echo '{"model":"opus"}' > "$HOME/.claude/settings.json"
  echo "# shared instructions" > "$HOME/.claude/CLAUDE.md"
  cat > "$HOME/.claude.json" <<'EOF'
{
  "hasCompletedOnboarding": true,
  "oauthAccount": {"emailAddress": "me@example.com", "organizationName": "Me"},
  "userID": "user-123",
  "anonymousId": "anon-456",
  "cachedGrowthBookFeatures": {"x": 1},
  "modelAccessCache": {"y": 2},
  "passesEligibilityCache": {},
  "mcpServers": {"shared-mcp": {"command": "shared"}},
  "projects": {"/repo/a": {"hasTrustDialogAccepted": true}}
}
EOF

  # A fake claude that reports the environment it was started with.
  cat > "$TESTTMP/fakebin/claude" <<'EOF'
#!/bin/sh
echo "CONFIG_DIR=${CLAUDE_CONFIG_DIR-<unset>}"
echo "PROFILE=${CLAUDE_AS_PROFILE-<unset>}"
echo "ARGS=$*"
EOF
  chmod +x "$TESTTMP/fakebin/claude"
  local repo_bin
  repo_bin="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd -P)"
  export PATH="$TESTTMP/fakebin:$repo_bin:$PATH"
}

teardown_isolated_env() {
  [ -n "${TESTTMP:-}" ] && rm -rf "$TESTTMP"
}

# ca <args...> — run claude-as under the chosen bash.
ca() { "$TEST_BASH" "$SCRIPT" "$@"; }

write_config() {
  mkdir -p "$XDG_CONFIG_HOME/claude-as"
  printf '%s\n' "$@" > "$XDG_CONFIG_HOME/claude-as/config"
}

# assert_link <path> <expected-target>
assert_link() {
  [ -L "$1" ] || { echo "not a symlink: $1"; return 1; }
  [ "$(readlink "$1")" = "$2" ] || { echo "$1 -> $(readlink "$1"), expected $2"; return 1; }
}

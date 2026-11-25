#!/usr/bin/env bats
# Test suite for claude-as. Runs against an isolated HOME; see helpers.bash.

bats_require_minimum_version 1.5.0
load helpers

setup()    { setup_isolated_env; }
teardown() { teardown_isolated_env; }

# --- CLI basics ----------------------------------------------------------------

@test "no arguments prints usage and exits 2" {
  run ca
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help and --help exit 0" {
  run ca help;   [ "$status" -eq 0 ]; [[ "$output" == *"claude-as <profile>"* ]]
  run ca --help; [ "$status" -eq 0 ]
}

@test "--version prints semver" {
  run ca --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^claude-as\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "unknown option exits 2" {
  run ca --bogus
  [ "$status" -eq 2 ]
}

@test "invalid and reserved profile names are rejected" {
  run ca Work;        [ "$status" -eq 2 ]
  run ca 'a/b';       [ "$status" -eq 2 ]
  run ca setup list;  [ "$status" -eq 2 ]; [[ "$output" == *"claude-as command"* ]]
  run ca setup as;    [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude-list" ]
}

# --- running claude --------------------------------------------------------------

@test "default profile runs claude with CLAUDE_CONFIG_DIR unset, even if inherited" {
  CLAUDE_CONFIG_DIR="$HOME/.claude-other" run ca default --resume abc
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"PROFILE=default"* ]]
  [[ "$output" == *"ARGS=--resume abc"* ]]
}

@test "default_aliases names the default profile" {
  write_config "default_aliases = personal, me"
  run ca personal
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"PROFILE=personal"* ]]
  [ ! -e "$HOME/.claude-personal" ]
}

@test "a named profile runs claude with its own CLAUDE_CONFIG_DIR" {
  run ca work -p "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]]
  [[ "$output" == *"PROFILE=work"* ]]
  [[ "$output" == *"ARGS=-p hello world"* ]]
}

@test "missing claude binary exits 127" {
  rm "$TESTTMP/fakebin/claude"
  PATH="$TESTTMP/fakebin:/usr/bin:/bin" run -127 ca work
  [ "$status" -eq 127 ]
  [[ "$output" == *"not found"* ]]
}

@test "CLAUDE_AS_BIN and claude_bin choose the binary" {
  mkdir -p "$TESTTMP/alt"
  printf '#!/bin/sh\necho ALT\n' > "$TESTTMP/alt/claude"; chmod +x "$TESTTMP/alt/claude"
  CLAUDE_AS_BIN="$TESTTMP/alt/claude" run ca work
  [ "$output" = ALT ] || [[ "$output" == *ALT ]]
  write_config "claude_bin = $TESTTMP/alt/claude"
  run ca work
  [[ "$output" == *ALT ]]
}

@test "refuses to exec itself as claude" {
  CLAUDE_AS_BIN="$SCRIPT" run -127 ca work
  [ "$status" -eq 127 ]
  [[ "$output" == *"is claude-as itself"* ]]
}

# --- profile setup -----------------------------------------------------------------

@test "setup links the shared items back to ~/.claude" {
  run ca setup work
  [ "$status" -eq 0 ]
  local d="$HOME/.claude-work"
  for n in settings.json CLAUDE.md history.jsonl skills agents commands output-styles plugins file-history todos; do
    assert_link "$d/$n" "$HOME/.claude/$n"
  done
  # Transcripts/memory and plans stay per profile by default (claude-code#98044).
  [ ! -L "$d/projects" ] && [ ! -L "$d/plans" ]
  [ -f "$d/.claude-as" ]
  # Shared dirs are created in the base so later additions are shared too.
  [ -d "$HOME/.claude/agents" ] && [ -d "$HOME/.claude/file-history" ]
  [ -f "$HOME/.claude/history.jsonl" ]
  # Optional items that do not exist are not linked.
  [ ! -e "$d/keybindings.json" ] && [ ! -L "$d/keybindings.json" ]
  [ ! -L "$d/hooks" ]
}

@test "profile dir is private (0700)" {
  ca setup work
  perms="$(ls -ld "$HOME/.claude-work" | cut -c1-10)"
  [ "$perms" = "drwx------" ]
}

@test "writes through a shared link land in ~/.claude" {
  ca setup work
  echo '{"model":"sonnet"}' > "$HOME/.claude-work/settings.json"
  grep -q sonnet "$HOME/.claude/settings.json"
  touch "$HOME/.claude-work/agents/reviewer.md"
  [ -f "$HOME/.claude/agents/reviewer.md" ]
}

@test "account file is seeded without identity or caches" {
  ca setup work
  local f="$HOME/.claude-work/.claude.json"
  [ -f "$f" ]
  [ "$(jq -r '.oauthAccount // "none"' "$f")" = none ]
  [ "$(jq -r '.userID // "none"' "$f")" = none ]
  [ "$(jq -r '.anonymousId // "none"' "$f")" = none ]
  [ "$(jq -r 'has("cachedGrowthBookFeatures") or has("modelAccessCache") or has("passesEligibilityCache")' "$f")" = false ]
  [ "$(jq -r '.hasCompletedOnboarding' "$f")" = true ]
  [ "$(jq -r '.projects["/repo/a"].hasTrustDialogAccepted' "$f")" = true ]
  [ "$(jq -r '.mcpServers["shared-mcp"].command' "$f")" = shared ]
  [ "$(ls -l "$f" | cut -c1-10)" = "-rw-------" ]
}

@test "an existing account file is never re-seeded" {
  mkdir -p "$HOME/.claude-work"
  echo '{"oauthAccount":{"emailAddress":"work@example.com"}}' > "$HOME/.claude-work/.claude.json"
  ca setup work
  [ "$(jq -r '.oauthAccount.emailAddress' "$HOME/.claude-work/.claude.json")" = work@example.com ]
}

@test "without jq, setup still works and skips seeding" {
  CLAUDE_AS_JQ=/nonexistent/jq run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq not found"* ]]
  [ ! -e "$HOME/.claude-work/.claude.json" ]
  assert_link "$HOME/.claude-work/settings.json" "$HOME/.claude/settings.json"
}

@test "setup never clobbers a real file in the profile" {
  mkdir -p "$HOME/.claude-work"
  echo '{"model":"local"}' > "$HOME/.claude-work/settings.json"
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"own copy, not the shared one"* ]]
  [ ! -L "$HOME/.claude-work/settings.json" ]
  grep -q local "$HOME/.claude-work/settings.json"
}

@test "setup is idempotent" {
  ca setup work
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" != *"own copy"* ]]
  [[ "$output" != *"created profile"* ]]
}

@test "share_add and share_skip adjust what is shared" {
  echo 'x' > "$HOME/.claude/statusline.sh"
  write_config "share_add = statusline.sh" "share_skip = history.jsonl, todos"
  ca setup work
  assert_link "$HOME/.claude-work/statusline.sh" "$HOME/.claude/statusline.sh"
  [ ! -e "$HOME/.claude-work/history.jsonl" ] && [ ! -L "$HOME/.claude-work/history.jsonl" ]
  [ ! -L "$HOME/.claude-work/todos" ]
}

@test "projects and plans can be opted in with share_add" {
  write_config "share_add = projects plans"
  ca setup work
  assert_link "$HOME/.claude-work/projects" "$HOME/.claude/projects"
  assert_link "$HOME/.claude-work/plans" "$HOME/.claude/plans"
}

@test "share entries can never include account state or paths" {
  write_config "share_add = .claude.json .credentials.json ../evil a/b"
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring share entry '.claude.json'"* ]]
  [[ "$output" == *"ignoring share entry '.credentials.json'"* ]]
  [ ! -L "$HOME/.claude-work/.claude.json" ]
  [ ! -L "$HOME/.claude-work/.credentials.json" ]
}

@test "setup of the default profile is a no-op" {
  run ca setup default
  [ "$status" -eq 0 ]
  [[ "$output" == *"default profile"* ]]
}

@test "custom base_dir exports CLAUDE_CONFIG_DIR for the default profile" {
  mkdir -p "$TESTTMP/base"
  echo '{}' > "$TESTTMP/base/settings.json"
  write_config "base_dir = $TESTTMP/base"
  run ca default
  [[ "$output" == *"CONFIG_DIR=$TESTTMP/base"* ]]
  ca setup work
  assert_link "$HOME/.claude-work/settings.json" "$TESTTMP/base/settings.json"
}

@test "missing base dir is an error" {
  rm -rf "$HOME/.claude"
  run ca setup work
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# --- claude-<profile> links ----------------------------------------------------------

@test "link creates claude-<profile> that runs as that profile with all args passed" {
  run ca link work "$TESTTMP/linkbin"
  [ "$status" -eq 0 ]
  [ -L "$TESTTMP/linkbin/claude-work" ]
  run "$TEST_BASH" "$TESTTMP/linkbin/claude-work" list --flag
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]]
  [[ "$output" == *"ARGS=list --flag"* ]]
}

@test "link refuses to replace an unrelated file" {
  mkdir -p "$TESTTMP/linkbin"
  echo 'other' > "$TESTTMP/linkbin/claude-work"
  run ca link work "$TESTTMP/linkbin"
  [ "$status" -ne 0 ]
  [ "$(cat "$TESTTMP/linkbin/claude-work")" = other ]
}

@test "link defaults to ~/.local/bin and warns when it is not on PATH" {
  run ca link work
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-work" ]
  [[ "$output" == *"not on your PATH"* ]]
}

# --- list / env / sync -------------------------------------------------------------

@test "list shows each profile's account and ignores unrelated ~/.claude-* dirs" {
  ca setup work
  jq '.oauthAccount = {"emailAddress":"work@example.com"}' "$HOME/.claude-work/.claude.json" > "$TESTTMP/t" &&
    mv "$TESTTMP/t" "$HOME/.claude-work/.claude.json"
  ca setup fresh
  mkdir -p "$HOME/.claude-code-router"
  CLAUDE_AS_PROFILE=work run ca list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"*"me@example.com"* ]]
  [[ "$output" == *"* work"*"work@example.com"* ]]
  [[ "$output" == *"fresh"*"(not logged in)"* ]]
  [[ "$output" != *"code-router"* ]]
}

@test "list falls back to sed without jq" {
  CLAUDE_AS_JQ=/nonexistent/jq run ca list
  [ "$status" -eq 0 ]
  [[ "$output" == *"me@example.com"* ]]
}

@test "env output can be eval'd" {
  eval "$(ca env work 2>/dev/null)"
  [ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-work" ]
  [ "$CLAUDE_AS_PROFILE" = work ]
  export CLAUDE_CONFIG_DIR=/x
  eval "$(ca env default 2>/dev/null)"
  [ -z "${CLAUDE_CONFIG_DIR+x}" ]
  [ "$CLAUDE_AS_PROFILE" = default ]
}

@test "sync adds missing MCP servers and projects; profile values win" {
  ca setup work
  local f="$HOME/.claude-work/.claude.json"
  jq '.mcpServers = {"shared-mcp": {"command": "mine"}, "work-only": {"command": "w"}} | .projects = {}' "$f" > "$TESTTMP/t" && mv "$TESTTMP/t" "$f"
  jq '.mcpServers["new-mcp"] = {"command": "new"} | .projects["/repo/b"] = {"hasTrustDialogAccepted": true}' "$HOME/.claude.json" > "$TESTTMP/t" &&
    mv "$TESTTMP/t" "$HOME/.claude.json"
  run ca sync work
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mcpServers["shared-mcp"].command' "$f")" = mine ]
  [ "$(jq -r '.mcpServers["work-only"].command' "$f")" = w ]
  [ "$(jq -r '.mcpServers["new-mcp"].command' "$f")" = new ]
  [ "$(jq -r '.projects["/repo/b"].hasTrustDialogAccepted' "$f")" = true ]
  [ "$(ls -l "$f" | cut -c1-10)" = "-rw-------" ]
}

@test "sync refuses the default profile" {
  run ca sync default
  [ "$status" -ne 0 ]
}

# --- doctor ------------------------------------------------------------------------

@test "doctor is clean on a fresh profile" {
  ca setup work
  run ca doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: all shared items linked"* ]]
}

@test "doctor detects a drifted file and --fix relinks, keeping the stray copy" {
  ca setup work
  rm "$HOME/.claude-work/settings.json"
  echo '{"model":"drifted"}' > "$HOME/.claude-work/settings.json"
  run ca doctor work
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift    settings.json"* ]]
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/settings.json" "$HOME/.claude/settings.json"
  ls "$HOME/.claude-work"/settings.json.claude-as-stray.* >/dev/null
  grep -q drifted "$HOME/.claude-work"/settings.json.claude-as-stray.*
  grep -q opus "$HOME/.claude/settings.json"
}

@test "doctor --fix adopts a profile-only item into the base" {
  ca setup work
  echo '{"bindings":[]}' > "$HOME/.claude-work/keybindings.json"
  run ca doctor work
  [ "$status" -eq 1 ]
  [[ "$output" == *"local    keybindings.json"* ]]
  ca doctor work --fix
  assert_link "$HOME/.claude-work/keybindings.json" "$HOME/.claude/keybindings.json"
  grep -q bindings "$HOME/.claude/keybindings.json"
}

@test "doctor reports and fixes missing and foreign links" {
  ca setup work
  rm "$HOME/.claude-work/skills"
  ln -s /elsewhere "$HOME/.claude-work/agents"
  run ca doctor work
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing  skills"* ]]
  [[ "$output" == *"foreign  agents"* ]]
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/skills" "$HOME/.claude/skills"
  assert_link "$HOME/.claude-work/agents" "$HOME/.claude/agents"
}

@test "doctor warns when CLAUDE_CONFIG_DIR points at ~/.claude" {
  CLAUDE_CONFIG_DIR="$HOME/.claude" run ca doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"plain claude will look logged out"* ]]
}

@test "doctor on an unknown profile fails" {
  run ca doctor nope
  [ "$status" -ne 0 ]
}

@test "doctor --fix links an identical drifted file without leaving a stray" {
  ca setup work
  rm "$HOME/.claude-work/settings.json"
  cp "$HOME/.claude/settings.json" "$HOME/.claude-work/settings.json"
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/settings.json" "$HOME/.claude/settings.json"
  ! ls "$HOME/.claude-work"/settings.json.claude-as-stray.* 2>/dev/null
}

@test "adopting an existing CLAUDE_CONFIG_DIR merges its directories into the shared ones" {
  # A profile someone made by hand with CLAUDE_CONFIG_DIR=~/.claude-work,
  # adopted with projects/ opted in to sharing.
  write_config "share_add = projects"
  local w="$HOME/.claude-work" b="$HOME/.claude"
  mkdir -p "$w/projects/-repo-a/memory" "$w/projects/-repo-z" "$w/skills/work-skill" "$w/skills/my-skill"
  mkdir -p "$b/projects/-repo-a/memory"
  echo old  > "$b/projects/-repo-a/s0.jsonl"
  echo new  > "$w/projects/-repo-a/s1.jsonl"
  echo z    > "$w/projects/-repo-z/s2.jsonl"
  echo base > "$b/projects/-repo-a/memory/MEMORY.md"
  echo work > "$w/projects/-repo-a/memory/MEMORY.md"
  echo '{"oauthAccount":{"emailAddress":"work@example.com"}}' > "$w/.claude.json"
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects is the profile's own copy"* ]]
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"skills: merged the profile's copy"* ]]
  [[ "$output" == *"projects: merged into"*"1 conflicting entry kept in"* ]]
  assert_link "$w/projects" "$b/projects"
  assert_link "$w/skills" "$b/skills"
  # Transcripts from both sides are now in the shared tree.
  [ "$(cat "$b/projects/-repo-a/s0.jsonl")" = old ]
  [ "$(cat "$b/projects/-repo-a/s1.jsonl")" = new ]
  [ "$(cat "$b/projects/-repo-z/s2.jsonl")" = z ]
  [ -d "$b/skills/work-skill" ] && [ -d "$b/skills/my-skill" ]
  # The conflicting file kept its shared version; the profile's version is preserved.
  [ "$(cat "$b/projects/-repo-a/memory/MEMORY.md")" = base ]
  [ "$(cat "$w"/projects.claude-as-stray.*/-repo-a/memory/MEMORY.md)" = work ]
  # The existing login is untouched.
  [ "$(jq -r .oauthAccount.emailAddress "$w/.claude.json")" = work@example.com ]
  run ca doctor work
  [ "$status" -eq 0 ]
}

# --- import ---------------------------------------------------------------------

make_session() { # <config-dir> <slug> <sid>
  mkdir -p "$1/projects/$2/$3/subagents"
  echo "{\"sessionId\":\"$3\"}" > "$1/projects/$2/$3.jsonl"
  echo sub > "$1/projects/$2/$3/subagents/agent-1.jsonl"
}

@test "import copies a session (and its subagent folder) into another profile" {
  make_session "$HOME/.claude" -repo-a 11111111-aaaa
  run ca import work 11111111-aaaa
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-as work --resume 11111111-aaaa"* ]]
  [ -f "$HOME/.claude-work/projects/-repo-a/11111111-aaaa.jsonl" ]
  [ "$(cat "$HOME/.claude-work/projects/-repo-a/11111111-aaaa/subagents/agent-1.jsonl")" = sub ]
  # The original is left in place.
  [ -f "$HOME/.claude/projects/-repo-a/11111111-aaaa.jsonl" ]
  run ca import work 11111111-aaaa
  [ "$status" -eq 0 ]
  [[ "$output" == *"already has session"* ]]
}

@test "import works back into the default profile" {
  ca setup work
  make_session "$HOME/.claude-work" -repo-b 22222222-bbbb
  run ca import default 22222222-bbbb
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/projects/-repo-b/22222222-bbbb.jsonl" ]
}

@test "import rejects unknown sessions and malformed ids" {
  run ca import work 99999999-none
  [ "$status" -ne 0 ]
  [[ "$output" == *"no other profile has"* ]]
  run ca import work '../../etc/passwd'
  [ "$status" -eq 2 ]
}

# --- robustness ---------------------------------------------------------------------

@test "links point at the final file when a base item is itself a symlink" {
  mkdir -p "$TESTTMP/dotfiles"
  mv "$HOME/.claude/settings.json" "$TESTTMP/dotfiles/settings.json"
  ln -s "$TESTTMP/dotfiles/settings.json" "$HOME/.claude/settings.json"
  ca setup work
  assert_link "$HOME/.claude-work/settings.json" "$TESTTMP/dotfiles/settings.json"
  run ca doctor work
  [ "$status" -eq 0 ]
}

@test "a trailing slash in HOME does not change the profile path" {
  HOME="$HOME/" run ca work
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]]
  [[ "$output" != *"//"* ]]
}

@test "doctor warns about credentials that override every profile" {
  ca setup work
  CLAUDE_CODE_OAUTH_TOKEN=x run ca doctor
  [[ "$output" == *"CLAUDE_CODE_OAUTH_TOKEN is set"* ]]
  echo '{"env":{"ANTHROPIC_API_KEY":"k"},"apiKeyHelper":"/bin/echo"}' > "$HOME/.claude/settings.json"
  run ca doctor
  [[ "$output" == *"shared settings.json sets ANTHROPIC_API_KEY, apiKeyHelper"* ]]
}

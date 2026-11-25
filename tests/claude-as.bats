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
  [[ "$output" == *"Usage:"* ]] || false
}

@test "help and --help exit 0" {
  run ca help;   [ "$status" -eq 0 ]; [[ "$output" == *"claude-as <profile>"* ]]
  run ca --help; [ "$status" -eq 0 ]
}

@test "--version prints semver" {
  run ca --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^claude-as\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || false
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
  [[ "$output" == *"CONFIG_DIR=<unset>"* ]] || false
  [[ "$output" == *"PROFILE=default"* ]] || false
  [[ "$output" == *"ARGS=--resume abc"* ]] || false
}

@test "default_aliases names the default profile" {
  write_config "default_aliases = personal, me"
  run ca personal
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_DIR=<unset>"* ]] || false
  [[ "$output" == *"PROFILE=personal"* ]] || false
  [ ! -e "$HOME/.claude-personal" ]
}

@test "a named profile runs claude with its own CLAUDE_CONFIG_DIR" {
  ca setup work
  run ca work -p "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]] || false
  [[ "$output" == *"PROFILE=work"* ]] || false
  [[ "$output" == *"ARGS=-p hello world"* ]] || false
}

@test "missing claude binary exits 127" {
  rm "$TESTTMP/fakebin/claude"
  PATH="$TESTTMP/fakebin:/usr/bin:/bin" run -127 ca work
  [ "$status" -eq 127 ]
  [[ "$output" == *"not found"* ]] || false
}

@test "CLAUDE_AS_BIN and claude_bin choose the binary" {
  mkdir -p "$TESTTMP/alt"
  printf '#!/bin/sh\necho ALT\n' > "$TESTTMP/alt/claude"; chmod +x "$TESTTMP/alt/claude"
  ca setup work
  CLAUDE_AS_BIN="$TESTTMP/alt/claude" run ca work
  [ "$output" = ALT ] || [[ "$output" == *ALT ]]
  write_config "claude_bin = $TESTTMP/alt/claude"
  run ca work
  [[ "$output" == *ALT ]] || false
}

@test "refuses to exec itself as claude" {
  CLAUDE_AS_BIN="$SCRIPT" run -127 ca work
  [ "$status" -eq 127 ]
  [[ "$output" == *"is claude-as itself"* ]] || false
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
  [ ! -L "$d/projects" ] && [ ! -L "$d/plans" ] || false
  [ -f "$d/.claude-as" ]
  # Shared dirs are created in the base so later additions are shared too.
  [ -d "$HOME/.claude/agents" ] && [ -d "$HOME/.claude/file-history" ] || false
  [ -f "$HOME/.claude/history.jsonl" ]
  # Optional items that do not exist are not linked.
  [ ! -e "$d/keybindings.json" ] && [ ! -L "$d/keybindings.json" ] || false
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
  [[ "$output" == *"jq not found"* ]] || false
  [ ! -e "$HOME/.claude-work/.claude.json" ]
  assert_link "$HOME/.claude-work/settings.json" "$HOME/.claude/settings.json"
}

@test "setup never clobbers a real file in the profile" {
  mkdir -p "$HOME/.claude-work"
  echo '{"model":"local"}' > "$HOME/.claude-work/settings.json"
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"own copy, not the shared one"* ]] || false
  [ ! -L "$HOME/.claude-work/settings.json" ]
  grep -q local "$HOME/.claude-work/settings.json"
}

@test "setup is idempotent" {
  ca setup work
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" != *"own copy"* ]] || false
  [[ "$output" != *"created profile"* ]] || false
}

@test "share_add and share_skip adjust what is shared" {
  echo 'x' > "$HOME/.claude/statusline.sh"
  write_config "share_add = statusline.sh" "share_skip = history.jsonl, todos"
  ca setup work
  assert_link "$HOME/.claude-work/statusline.sh" "$HOME/.claude/statusline.sh"
  [ ! -e "$HOME/.claude-work/history.jsonl" ] && [ ! -L "$HOME/.claude-work/history.jsonl" ] || false
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
  [[ "$output" == *"ignoring share entry '.claude.json'"* ]] || false
  [[ "$output" == *"ignoring share entry '.credentials.json'"* ]] || false
  [ ! -L "$HOME/.claude-work/.claude.json" ]
  [ ! -L "$HOME/.claude-work/.credentials.json" ]
}

@test "setup of the default profile is a no-op" {
  run ca setup default
  [ "$status" -eq 0 ]
  [[ "$output" == *"default profile"* ]] || false
}

@test "custom base_dir exports CLAUDE_CONFIG_DIR for the default profile" {
  mkdir -p "$TESTTMP/base"
  echo '{}' > "$TESTTMP/base/settings.json"
  write_config "base_dir = $TESTTMP/base"
  run ca default
  [[ "$output" == *"CONFIG_DIR=$TESTTMP/base"* ]] || false
  ca setup work
  assert_link "$HOME/.claude-work/settings.json" "$TESTTMP/base/settings.json"
}

@test "missing base dir is an error" {
  rm -rf "$HOME/.claude"
  run ca setup work
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || false
}

# --- claude-<profile> links ----------------------------------------------------------

@test "link creates claude-<profile> that runs as that profile with all args passed" {
  ca setup work
  run ca link work "$TESTTMP/linkbin"
  [ "$status" -eq 0 ]
  [ -L "$TESTTMP/linkbin/claude-work" ]
  run "$TEST_BASH" "$TESTTMP/linkbin/claude-work" list --flag
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]] || false
  [[ "$output" == *"ARGS=list --flag"* ]] || false
}

@test "link refuses to replace an unrelated file" {
  mkdir -p "$TESTTMP/linkbin"
  echo 'other' > "$TESTTMP/linkbin/claude-work"
  run ca link work "$TESTTMP/linkbin"
  [ "$status" -ne 0 ]
  [ "$(cat "$TESTTMP/linkbin/claude-work")" = other ]
}

@test "link defaults to ~/.local/bin and warns when it is not on PATH" {
  ca setup work
  run ca link work
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-work" ]
  [[ "$output" == *"not on your PATH"* ]] || false
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
  [[ "$output" == *"default"*"me@example.com"* ]] || false
  [[ "$output" == *"* work"*"work@example.com"* ]] || false
  [[ "$output" == *"fresh"*"(not logged in)"* ]] || false
  [[ "$output" != *"code-router"* ]] || false
}

@test "list falls back to sed without jq" {
  CLAUDE_AS_JQ=/nonexistent/jq run ca list
  [ "$status" -eq 0 ]
  [[ "$output" == *"me@example.com"* ]] || false
}

@test "env output can be eval'd" {
  ca setup work
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
  [[ "$output" == *"ok: all shared items linked"* ]] || false
}

@test "doctor detects a drifted file and --fix relinks, keeping the stray copy" {
  ca setup work
  rm "$HOME/.claude-work/settings.json"
  echo '{"model":"drifted"}' > "$HOME/.claude-work/settings.json"
  run ca doctor work
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift    settings.json"* ]] || false
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
  [[ "$output" == *"local    keybindings.json"* ]] || false
  ca doctor work --fix
  assert_link "$HOME/.claude-work/keybindings.json" "$HOME/.claude/keybindings.json"
  grep -q bindings "$HOME/.claude/keybindings.json"
}

@test "doctor reports and fixes missing and foreign links" {
  ca setup work
  rm "$HOME/.claude-work/skills"
  ln -sfn /elsewhere "$HOME/.claude-work/agents"   # -n: replace the link, do not descend into it (GNU ln)
  run ca doctor work
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing  skills"* ]] || false
  [[ "$output" == *"foreign  agents"* ]] || false
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/skills" "$HOME/.claude/skills"
  assert_link "$HOME/.claude-work/agents" "$HOME/.claude/agents"
}

@test "doctor warns when CLAUDE_CONFIG_DIR points at ~/.claude" {
  CLAUDE_CONFIG_DIR="$HOME/.claude" run ca doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"plain claude will look logged out"* ]] || false
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
  for f in "$HOME/.claude-work"/settings.json.claude-as-stray.*; do [ ! -e "$f" ]; done
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
  [[ "$output" == *"projects is the profile's own copy"* ]] || false
  run ca doctor work --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"skills: merged the profile's copy"* ]] || false
  [[ "$output" == *"projects: merged into"*"kept 1 differing entry in"* ]] || false
  assert_link "$w/projects" "$b/projects"
  assert_link "$w/skills" "$b/skills"
  # Transcripts from both sides are now in the shared tree.
  [ "$(cat "$b/projects/-repo-a/s0.jsonl")" = old ]
  [ "$(cat "$b/projects/-repo-a/s1.jsonl")" = new ]
  [ "$(cat "$b/projects/-repo-z/s2.jsonl")" = z ]
  [ -d "$b/skills/work-skill" ] && [ -d "$b/skills/my-skill" ] || false
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
  ca setup work
  make_session "$HOME/.claude" -repo-a 11111111-aaaa
  run ca import work 11111111-aaaa
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-as work --resume 11111111-aaaa"* ]] || false
  [ -f "$HOME/.claude-work/projects/-repo-a/11111111-aaaa.jsonl" ]
  [ "$(cat "$HOME/.claude-work/projects/-repo-a/11111111-aaaa/subagents/agent-1.jsonl")" = sub ]
  # The original is left in place.
  [ -f "$HOME/.claude/projects/-repo-a/11111111-aaaa.jsonl" ]
  run ca import work 11111111-aaaa
  [ "$status" -eq 0 ]
  [[ "$output" == *"already has session"* ]] || false
}

@test "import works back into the default profile" {
  ca setup work
  make_session "$HOME/.claude-work" -repo-b 22222222-bbbb
  run ca import default 22222222-bbbb
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/projects/-repo-b/22222222-bbbb.jsonl" ]
}

@test "import rejects unknown sessions and malformed ids" {
  ca setup work
  run ca import work 99999999-none
  [ "$status" -ne 0 ]
  [[ "$output" == *"no other profile has"* ]] || false
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
  ca setup work
  HOME="$HOME/" run ca work
  [[ "$output" == *"CONFIG_DIR=$HOME/.claude-work"* ]] || false
  [[ "$output" != *"//"* ]] || false
}

@test "doctor warns about credentials that override every profile" {
  ca setup work
  CLAUDE_CODE_OAUTH_TOKEN=x run ca doctor
  [[ "$output" == *"CLAUDE_CODE_OAUTH_TOKEN is set"* ]] || false
  echo '{"env":{"ANTHROPIC_API_KEY":"k"},"apiKeyHelper":"/bin/echo"}' > "$HOME/.claude/settings.json"
  run ca doctor
  [[ "$output" == *"shared settings.json sets ANTHROPIC_API_KEY, apiKeyHelper"* ]] || false
}

# --- many accounts ----------------------------------------------------------------

@test "any number of profiles coexist, each with its own config dir, all sharing one setup" {
  for p in a b c d; do ca setup "$p" >/dev/null 2>&1; done
  for p in a b c d; do
    run ca "$p"
    [[ "$output" == *"CONFIG_DIR=$HOME/.claude-$p"* ]] || false
    assert_link "$HOME/.claude-$p/settings.json" "$HOME/.claude/settings.json"
  done
  run ca list
  [ "$(echo "$output" | grep -cE '^[ *] (default|a|b|c|d) ')" -eq 5 ]
  run ca doctor
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'ok: all shared items linked')" -eq 4 ]
}

@test "import moves a session between two non-default profiles" {
  ca setup a; ca setup b
  make_session "$HOME/.claude-a" -repo-c 33333333-cccc
  run ca import b 33333333-cccc
  [ "$status" -eq 0 ]
  [[ "$output" == *"from ~/.claude-a into ~/.claude-b"* ]] || false
  [ -f "$HOME/.claude-b/projects/-repo-c/33333333-cccc.jsonl" ]
}

# --- guarding against typos ---------------------------------------------------------

@test "running a profile that does not exist fails without a terminal, and creates nothing" {
  run ca acme2 -p hi < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"there is no profile 'acme2' (create it with: claude-as setup acme2)"* ]] || false
  [ ! -e "$HOME/.claude-acme2" ]
}

@test "claude's own subcommands are not profile names" {
  run ca auth login
  [ "$status" -eq 2 ]
  [[ "$output" == *"'auth' is a claude command"*"claude-as <profile> auth"* ]] || false
  run ca mcp list
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude-auth" ] && [ ! -e "$HOME/.claude-mcp" ] || false
}

@test "env, import and sync need an existing profile" {
  run ca env nope;            [ "$status" -eq 1 ]
  run ca import nope abc-123; [ "$status" -eq 1 ]
  run ca sync nope;           [ "$status" -eq 1 ]
  [ ! -e "$HOME/.claude-nope" ]
}

@test "link warns when the profile does not exist yet" {
  run ca link later "$TESTTMP/linkbin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"there is no profile 'later' yet"* ]] || false
}

# --- config parsing -------------------------------------------------------------------

@test "list settings accumulate across lines; unknown keys and bad lines warn" {
  echo x > "$HOME/.claude/a.txt"; echo y > "$HOME/.claude/b.txt"
  write_config "share_add = a.txt" "share_add = b.txt" "  # a comment" "sharre_skip = todos" "nonsense"
  run ca setup work
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/a.txt" "$HOME/.claude/a.txt"
  assert_link "$HOME/.claude-work/b.txt" "$HOME/.claude/b.txt"
  [[ "$output" == *"unknown setting 'sharre_skip'"* ]] || false
  [[ "$output" == *"expected 'key = value'"* ]] || false
}

@test "a glob in share_add stays literal and is rejected" {
  touch "$HOME/.claude/zz-should-not-link"
  write_config "share_add = * zz-*"
  run ca setup work
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring share entry '*'"* ]] || false
  [ ! -L "$HOME/.claude-work/zz-should-not-link" ]
}

@test "list sizes its columns to the content" {
  local a_name=a-much-longer-profile-name
  ca setup "$a_name"
  run ca list
  [ "$status" -eq 0 ]
  # Header and rows line up: ACCOUNT starts in the same column everywhere.
  local hdr row hpre rpre
  hdr="$(echo "$output" | sed -n 1p)"; row="$(echo "$output" | grep 'a-much-longer')"
  hpre="${hdr%%ACCOUNT*}"; rpre="${row%%(not logged in)*}"
  [ "${#hpre}" -eq "${#rpre}" ]
  # ...and no wider than the longest name needs.
  [ "${#hpre}" -eq $(( 2 + ${#a_name} + 3 )) ] || [ "${#hpre}" -eq 31 ]
}

# --- data safety (regressions from the pre-announcement review) ---------------------

@test "doctor --fix never touches the base when an old profile name becomes a default alias" {
  ca setup personal
  write_config "default_aliases = personal"
  run ca doctor --fix
  # The stale profile is not treated as a profile at all, and ~/.claude is intact.
  [[ "$output" != *"profile personal"* ]] || false
  [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ] || false
  [ -d "$HOME/.claude/skills/my-skill" ] && [ ! -L "$HOME/.claude/skills" ] || false
  grep -q opus "$HOME/.claude/settings.json"
}

@test "a profile whose folder is the base directory is refused" {
  mkdir -p "$HOME/.claude-main"
  echo '{"model":"opus"}' > "$HOME/.claude-main/settings.json"
  write_config "base_dir = ~/.claude-main"
  run ca setup main
  [ "$status" -eq 2 ]
  [[ "$output" == *"is your base directory"* ]] || false
  [ -f "$HOME/.claude-main/settings.json" ] && [ ! -L "$HOME/.claude-main/settings.json" ] || false
}

@test "doctor --fix refuses to merge a base item that links back into the profile" {
  ca setup work
  # ~/.claude/agents is a link into the profile's own agents folder.
  rm "$HOME/.claude-work/agents"; mkdir "$HOME/.claude-work/agents"; echo keep > "$HOME/.claude-work/agents/a.md"
  rmdir "$HOME/.claude/agents"; ln -s "$HOME/.claude-work/agents" "$HOME/.claude/agents"
  run ca doctor work --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKIPPED  agents"* ]] || false
  [ "$(cat "$HOME/.claude-work/agents/a.md")" = keep ]
}

@test "concurrent first launches all start claude and never nest links in the base" {
  ca setup race >/dev/null 2>&1; rm -rf "$HOME/.claude-race"; mkdir -p "$HOME/.claude-race"
  echo "claude-as profile: race" > "$HOME/.claude-race/.claude-as"
  local i
  for i in 1 2 3 4 5 6; do ( ca race > "$TESTTMP/out.$i" 2>&1; echo $? > "$TESTTMP/rc.$i" ) & done
  wait
  for i in 1 2 3 4 5 6; do
    [ "$(cat "$TESTTMP/rc.$i")" = 0 ] || { cat "$TESTTMP/out.$i"; false; }
  done
  for n in skills agents commands plugins todos file-history; do
    [ ! -e "$HOME/.claude/$n/$n" ] && [ ! -L "$HOME/.claude/$n/$n" ] || false
  done
}

@test "doctor --fix reports a failed move instead of claiming success" {
  [ "$(id -u)" != 0 ] || skip "root ignores permissions"
  ca setup work
  mkdir -p "$HOME/.claude-work/hooks"; echo h > "$HOME/.claude-work/hooks/pre.sh"
  chmod 555 "$HOME/.claude"
  run ca doctor work --fix
  chmod 755 "$HOME/.claude"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED   hooks"* ]] || false
  [ -f "$HOME/.claude-work/hooks/pre.sh" ]
  [ ! -L "$HOME/.claude-work/hooks/hooks" ]
}

@test "doctor --fix drops identical read-only files without prompting" {
  ca setup work
  rm "$HOME/.claude-work/plugins"; mkdir -p "$HOME/.claude-work/plugins/m" "$HOME/.claude/plugins/m"
  echo pack > "$HOME/.claude/plugins/m/obj"; cp "$HOME/.claude/plugins/m/obj" "$HOME/.claude-work/plugins/m/obj"
  chmod 444 "$HOME/.claude-work/plugins/m/obj"
  run ca doctor work --fix < /dev/null
  [ "$status" -eq 0 ]
  assert_link "$HOME/.claude-work/plugins" "$HOME/.claude/plugins"
}

@test "import into a profile that already has the session folder does not nest it" {
  ca setup work
  make_session "$HOME/.claude" -repo-n 44444444-dddd
  mkdir -p "$HOME/.claude-work/projects/-repo-n/44444444-dddd/subagents"   # e.g. an interrupted import
  run ca import work 44444444-dddd
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude-work/projects/-repo-n/44444444-dddd/subagents/agent-1.jsonl" ]
  [ ! -e "$HOME/.claude-work/projects/-repo-n/44444444-dddd/44444444-dddd" ]
  [ -f "$HOME/.claude-work/projects/-repo-n/44444444-dddd.jsonl" ]
}

@test "a relative base_dir is rejected" {
  write_config "base_dir = .claude-main"
  run ca list
  [ "$status" -eq 1 ]
  [[ "$output" == *"base_dir must be an absolute path"* ]] || false
}

@test "link replaces a dead link left by an earlier install" {
  ca setup work
  mkdir -p "$TESTTMP/linkbin"
  ln -s "$TESTTMP/gone/bin/claude-as" "$TESTTMP/linkbin/claude-work"
  run ca link work "$TESTTMP/linkbin"
  [ "$status" -eq 0 ]
  [ -e "$TESTTMP/linkbin/claude-work" ]
}


#!/bin/bash
# Sandbox for docs/demo.tape. Everything lives under /tmp/claude-as-demo: a
# throwaway HOME and a stand-in `claude` that only implements `auth login` and
# `auth status` (same JSON shape as the real `claude auth status`). No real
# Claude state, credentials or accounts are read or written. Source it from
# the repo root.

DEMO_REPO=$(pwd)
DEMO=/tmp/claude-as-demo
rm -rf "$DEMO"
mkdir -p "$DEMO/bin" "$DEMO/home/.claude/skills/review" "$DEMO/home/.claude/projects" "$DEMO/home/.config/claude-as" "$DEMO/home/.local/bin"
cp "$DEMO_REPO/bin/claude-as" "$DEMO/bin/claude-as"

cat > "$DEMO/bin/claude" <<'STANDIN'
#!/bin/bash
# Stand-in for claude: keeps the "login" in the profile's .claude.json.
f="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
[ -n "${CLAUDE_CONFIG_DIR:-}" ] || f="$HOME/.claude.json"
case "$1 $2" in
  "auth login")
    email="me@${CLAUDE_AS_PROFILE:-default}.example"
    jq --arg e "$email" '.oauthAccount = {emailAddress: $e}' "$f" > "$f.t" && mv "$f.t" "$f"
    echo "Login successful." ;;
  "auth status")
    jq '{loggedIn: (.oauthAccount != null), authMethod: "claude.ai", email: .oauthAccount.emailAddress}' "$f" ;;
  *) echo "(demo stand-in for claude)" ;;
esac
STANDIN
chmod +x "$DEMO/bin/claude" "$DEMO/bin/claude-as"

echo '{"model": "opus"}' > "$DEMO/home/.claude/settings.json"
echo '{"hasCompletedOnboarding": true, "oauthAccount": {"emailAddress": "me@example.com"}}' > "$DEMO/home/.claude.json"

export HOME="$DEMO/home"
export PATH="$DEMO/bin:$HOME/.local/bin:$PATH"
unset CLAUDE_CONFIG_DIR CLAUDE_AS_PROFILE
cd "$HOME" || return
export PS1='$ '

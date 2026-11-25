#!/bin/bash
# Installer for claude-as. Works two ways:
#   - from a clone:   ./install.sh
#   - via curl:       curl -fsSL https://raw.githubusercontent.com/SteveVitali/claude-as/main/install.sh | bash
# Installs one self-contained bash script; nothing else.
set -eu

# The latest release's script (a release asset), so curl installs match Homebrew.
SCRIPT_URL="${CLAUDE_AS_URL:-https://github.com/SteveVitali/claude-as/releases/latest/download/claude-as}"
PREFIX="${CLAUDE_AS_PREFIX:-$HOME/.local/bin}"
TARGET="$PREFIX/claude-as"

mkdir -p "$PREFIX"

# Run as ./install.sh from a clone: install that checkout. Piped into bash,
# $0 is "bash", so never pick up a bin/claude-as from the current directory.
script_dir=""
case "$0" in
  */install.sh|install.sh) script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || script_dir="" ;;
esac
if [ -n "$script_dir" ] && [ -f "$script_dir/bin/claude-as" ]; then
  cp "$script_dir/bin/claude-as" "$TARGET.tmp.$$"
else
  echo "Downloading claude-as..."
  curl -fsSL "$SCRIPT_URL" -o "$TARGET.tmp.$$"
fi
chmod +x "$TARGET.tmp.$$"
mv "$TARGET.tmp.$$" "$TARGET"

echo "Installed: $TARGET ($("$TARGET" --version))"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    echo ""
    echo "NOTE: $PREFIX is not on your PATH. Add this to your shell profile:"
    echo "  export PATH=\"$PREFIX:\$PATH\""
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo ""
  echo "NOTE: jq was not found. claude-as works without it, but new profiles will"
  echo "start without your onboarding, project trust and MCP servers, and 'sync' needs it."
fi

echo ""
echo "Next steps:"
echo "  claude-as setup acme         # create a profile for another account"
echo "  claude-as acme auth login    # sign in to it"
echo "  claude-as link acme          # optional: adds a 'claude-acme' command"
echo "  claude-as list"

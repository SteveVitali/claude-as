#!/bin/bash
# Installer for claude-as. Works two ways:
#   - from a clone:   ./install.sh
#   - via curl:       curl -fsSL https://raw.githubusercontent.com/SteveVitali/claude-as/main/install.sh | bash
# Installs one self-contained bash script; nothing else.
set -eu

REPO_RAW="${CLAUDE_AS_RAW_URL:-https://raw.githubusercontent.com/SteveVitali/claude-as/main}"
PREFIX="${CLAUDE_AS_PREFIX:-$HOME/.local/bin}"
TARGET="$PREFIX/claude-as"

mkdir -p "$PREFIX"

script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || script_dir=""
if [ -n "$script_dir" ] && [ -f "$script_dir/bin/claude-as" ]; then
  cp "$script_dir/bin/claude-as" "$TARGET.tmp.$$"
else
  echo "Downloading claude-as..."
  curl -fsSL "$REPO_RAW/bin/claude-as" -o "$TARGET.tmp.$$"
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
  echo "not inherit your onboarding/project trust/MCP servers, and 'sync' needs it."
fi

echo ""
echo "Next steps:"
echo "  claude-as work auth login    # create a 'work' profile and sign in"
echo "  claude-as link work          # optional: adds a 'claude-work' command"
echo "  claude-as list"

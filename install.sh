#!/bin/bash
# ============================================================================
# clawd-line installer
# ============================================================================
# Copies clawd-line.sh into ~/.claude/, makes sure jq is available, and
# points Claude Code's statusLine at it - without touching any other key in
# settings.json. Safe to re-run: it only ever replaces the "statusLine"
# object and takes a timestamped backup of settings.json first.
#
# Works both ways:
#   curl -fsSL https://raw.githubusercontent.com/virvick/clawd-line/main/install.sh | bash
#   git clone https://github.com/virvick/clawd-line.git && cd clawd-line && ./install.sh
# In piped mode there's no local sibling file to copy from, so it downloads
# clawd-line.sh from the same raw URL instead.
# ============================================================================
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/virvick/clawd-line/main"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"

echo "clawd-line installer"
echo "====================="

mkdir -p "$CLAUDE_DIR"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but not found on PATH."
    if command -v brew >/dev/null 2>&1; then
        echo "Installing jq via Homebrew..."
        brew install jq
    elif command -v apt-get >/dev/null 2>&1; then
        echo "Installing jq via apt..."
        sudo apt-get update && sudo apt-get install -y jq
    else
        echo "Please install jq manually (https://jqlang.org/download/) and re-run this script."
        exit 1
    fi
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/clawd-line.sh" ]]; then
    echo "Copying clawd-line.sh to $CLAUDE_DIR/..."
    cp "$SCRIPT_DIR/clawd-line.sh" "$CLAUDE_DIR/clawd-line.sh"
else
    echo "Downloading clawd-line.sh to $CLAUDE_DIR/..."
    curl -fsSL "$REPO_RAW_BASE/clawd-line.sh" -o "$CLAUDE_DIR/clawd-line.sh"
fi
chmod +x "$CLAUDE_DIR/clawd-line.sh"

if [[ -f "$SETTINGS" ]]; then
    BACKUP="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    echo "Existing settings.json backed up to $BACKUP"
    jq '.statusLine = {"type": "command", "command": "bash ~/.claude/clawd-line.sh", "refreshInterval": 1}' \
        "$SETTINGS" > "$SETTINGS.tmp"
    mv "$SETTINGS.tmp" "$SETTINGS"
else
    cat > "$SETTINGS" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/clawd-line.sh",
    "refreshInterval": 1
  }
}
EOF
fi

echo "Done. statusLine now points at ~/.claude/clawd-line.sh."
echo "Restart Claude Code (or open a new session) to see it."

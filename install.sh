#!/usr/bin/env bash
# Installer for ralph-cursor scripts
# Usage:
#   cd your-project
#   curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/main/install.sh | bash

set -euo pipefail

PROJECT_DIR="$(pwd)"
SCRIPTS_DIR="$PROJECT_DIR/.cursor/ralph-scripts"
RAW_BASE="https://raw.githubusercontent.com/erikchan1000/ralph-cursor/main/scripts"

echo "Installing Ralph scripts into: $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

FILES=(
  "ralph-common.sh"
  "ralph-loop.sh"
  "ralph-once.sh"
  "ralph-setup.sh"
  "stream-parser.sh"
  "init-ralph.sh"
)

for f in "${FILES[@]}"; do
  echo "  - Fetching $f"
  curl -fsSL "$RAW_BASE/$f" -o "$SCRIPTS_DIR/$f"
done

chmod +x "$SCRIPTS_DIR"/*.sh || true

echo ""
echo "✓ Ralph scripts installed."
echo ""
echo "Next steps:"
echo "  1) Ensure dependencies are installed:"
echo "     - macOS:   brew install jq bc gum"
echo "     - Ubuntu:  sudo apt-get update && sudo apt-get install -y jq bc"
echo "  2) Initialize Ralph files (optional, creates .ralph/ and a template task):"
echo "     ./.cursor/ralph-scripts/init-ralph.sh"
echo "  3) Run interactive setup:"
echo "     ./.cursor/ralph-scripts/ralph-setup.sh"
echo ""
echo "Monitor progress with:"
echo "  tail -f .ralph/activity.log"
echo ""

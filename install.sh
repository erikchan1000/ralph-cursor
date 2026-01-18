#!/usr/bin/env bash
# Installer for ralph-cursor scripts
# Usage:
#   cd your-project
#   curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/master/install.sh | bash
#   # Optional: auto-install gum (and optionally jq/bc) if missing:
#   # curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/master/install.sh | bash -s -- --install-gum
#   # or:
#   # curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/master/install.sh | bash -s -- --install-deps

set -euo pipefail

PROJECT_DIR="$(pwd)"
SCRIPTS_DIR="$PROJECT_DIR/.cursor/ralph-scripts"
RAW_BASE="https://raw.githubusercontent.com/erikchan1000/ralph-cursor/master/scripts"

INSTALL_GUM_ONLY=0
INSTALL_ALL_DEPS=0

# Parse optional flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-gum)
      INSTALL_GUM_ONLY=1
      shift
      ;;
    --install-deps)
      INSTALL_ALL_DEPS=1
      shift
      ;;
    *)
      # ignore unknown flags/args
      shift
      ;;
  esac
done

has_cmd() { command -v "$1" >/dev/null 2>&1; }

try_install_pkg() {
  # $1 = package name
  local pkg="$1"
  if has_cmd brew; then
    brew install "$pkg" || return 1
    return 0
  fi
  if has_cmd apt-get; then
    sudo apt-get update -y && sudo apt-get install -y "$pkg" || return 1
    return 0
  fi
  if has_cmd dnf; then
    sudo dnf install -y "$pkg" || return 1
    return 0
  fi
  if has_cmd pacman; then
    sudo pacman -Sy --noconfirm "$pkg" || return 1
    return 0
  fi
  if has_cmd snap; then
    sudo snap install "$pkg" || return 1
    return 0
  fi
  return 1
}

ensure_gum() {
  if has_cmd gum; then
    return 0
  fi
  echo "gum not found; attempting to install..." >&2
  if try_install_pkg gum; then
    echo "✓ Installed gum"
    return 0
  fi
  # Fallback via Go if present
  if has_cmd go; then
    echo "Attempting go install for gum..." >&2
    GO111MODULE=on go install github.com/charmbracelet/gum@latest || true
    if has_cmd gum; then
      echo "✓ Installed gum via go"
      return 0
    fi
  fi
  echo "⚠️ Could not auto-install gum. Please install manually:" >&2
  echo "   • macOS:  brew install gum" >&2
  echo "   • Ubuntu: sudo apt-get update && sudo apt-get install -y gum" >&2
  echo "   • Docs:   https://github.com/charmbracelet/gum#installation" >&2
  return 1
}

ensure_jq_bc() {
  local missing=0
  if ! has_cmd jq; then
    echo "jq not found; attempting to install..." >&2
    if ! try_install_pkg jq; then
      echo "⚠️ Could not auto-install jq. Install manually (brew/apt/etc.)." >&2
      missing=1
    else
      echo "✓ Installed jq"
    fi
  fi
  if ! has_cmd bc; then
    echo "bc not found; attempting to install..." >&2
    if ! try_install_pkg bc; then
      echo "⚠️ Could not auto-install bc. Install manually (brew/apt/etc.)." >&2
      missing=1
    else
      echo "✓ Installed bc"
    fi
  fi
  return $missing
}

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
# Optionally install dependencies
if [[ "$INSTALL_ALL_DEPS" -eq 1 ]]; then
  ensure_gum || true
  ensure_jq_bc || true
elif [[ "$INSTALL_GUM_ONLY" -eq 1 ]]; then
  ensure_gum || true
fi

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
echo "During runs, updates are mirrored to this terminal; tailing is optional."
echo "You can also monitor via:"
echo "  tail -f .ralph/activity.log"
echo ""

#!/bin/bash
# Ralph Wiggum: The Loop (CLI Mode)
#
# Runs the Cursor agent locally with stream-json parsing for accurate token tracking.
# Handles context rotation via --resume when thresholds are hit.
#
# Usage:
#   ./ralph-loop.sh                              # Start from current directory
#   ./ralph-loop.sh /path/to/project             # Start from specific project
#   ./ralph-loop.sh -n 50 -m gpt-5.2-high        # Custom iterations and model
#   ./ralph-loop.sh --branch feature/foo --pr   # Create branch and PR
#   ./ralph-loop.sh -y                           # Skip confirmation (for scripting)
#
# Environment:
#   RALPH_MODEL          Override default model (same as -m)
#   RALPH_AGENT_BIN      Agent binary to use: "cursor-agent" or "agent" (default: cursor-agent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ralph-common.sh"

# -----------------------------------------------------------------------------
# Defaults (must exist under set -u)
# -----------------------------------------------------------------------------
WORKSPACE="${WORKSPACE:-}"
MODEL="${MODEL:-${RALPH_MODEL:-opus-4.5-thinking}}"
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"

USE_BRANCH="${USE_BRANCH:-}"
OPEN_PR="${OPEN_PR:-false}"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"

# Prefer `cursor-agent` by default for broader compatibility; can override to `agent`.
export RALPH_AGENT_BIN="${RALPH_AGENT_BIN:-cursor-agent}"

# =============================================================================
# FLAG PARSING
# =============================================================================

show_help() {
  cat << 'EOF'
Ralph Wiggum: The Loop (CLI Mode)

Usage:
  ./ralph-loop.sh [options] [workspace]

Options:
  -n, --iterations N     Max iterations (default: 20)
  -m, --model MODEL      Model to use (default: opus-4.5-thinking)
  --branch NAME          Create and work on a new branch
  --pr                   Open PR when complete (requires --branch)
  -y, --yes              Skip confirmation prompt
  -h, --help             Show this help

Examples:
  ./ralph-loop.sh
  ./ralph-loop.sh -n 50
  ./ralph-loop.sh -m gpt-5.2-high
  ./ralph-loop.sh --branch feature/api --pr -y

Environment:
  RALPH_MODEL            Override default model (same as -m)
  RALPH_AGENT_BIN        "cursor-agent" or "agent" (default: cursor-agent)
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    -m|--model)
      MODEL="$2"
      shift 2
      ;;
    --branch)
      USE_BRANCH="$2"
      shift 2
      ;;
    --pr)
      OPEN_PR="true"
      shift
      ;;
    -y|--yes)
      SKIP_CONFIRM="true"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use -h for help."
      exit 1
      ;;
    *)
      WORKSPACE="$1"
      shift
      ;;
  esac
done

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Resolve workspace
  if [[ -z "${WORKSPACE}" ]] || [[ "${WORKSPACE}" == "." ]]; then
    WORKSPACE="$(pwd)"
  else
    WORKSPACE="$(cd "$WORKSPACE" && pwd)"
  fi

  local task_file="$WORKSPACE/RALPH_TASK.md"

  show_banner

  if ! check_prerequisites "$WORKSPACE"; then
    exit 1
  fi

  # Validate: PR requires branch
  if [[ "$OPEN_PR" == "true" ]] && [[ -z "$USE_BRANCH" ]]; then
    echo "❌ --pr requires --branch"
    echo "   Example: ./ralph-loop.sh --branch feature/foo --pr"
    exit 1
  fi

  init_ralph_dir "$WORKSPACE"

  echo "Workspace: $WORKSPACE"
  echo "Task:      $task_file"
  echo "Model:     $MODEL"
  echo "Agent bin: $RALPH_AGENT_BIN"
  echo "Max iter:  $MAX_ITERATIONS"
  [[ -n "$USE_BRANCH" ]] && echo "Branch:    $USE_BRANCH"
  [[ "$OPEN_PR" == "true" ]] && echo "Open PR:   Yes"
  echo ""

  echo "📋 Task Summary:"
  echo "─────────────────────────────────────────────────────────────────"
  head -30 "$task_file"
  echo "─────────────────────────────────────────────────────────────────"
  echo ""

  # Count criteria
  local total_criteria done_criteria remaining
  total_criteria=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[(x| )\]' "$task_file" 2>/dev/null || echo 0)
  done_criteria=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[x\]' "$task_file" 2>/dev/null || echo 0)
  remaining=$((total_criteria - done_criteria))

  echo "Progress: $done_criteria / $total_criteria criteria complete ($remaining remaining)"
  echo ""

  if [[ "$remaining" -eq 0 ]] && [[ "$total_criteria" -gt 0 ]]; then
    echo "🎉 Task already complete! All criteria are checked."
    exit 0
  fi

  if [[ "$SKIP_CONFIRM" != "true" ]]; then
    echo "This will run the agent locally to work on this task."
    echo "The agent will be rotated when context fills up (~80k tokens)."
    echo ""
    read -p "Start Ralph loop? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  # Run loop (implementation is in ralph-common.sh)
  run_ralph_loop "$WORKSPACE" "$SCRIPT_DIR"
}

main


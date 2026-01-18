#!/bin/bash
# Ralph Wiggum: Stream Parser
#
# Parses cursor-agent stream-json output in real-time.
# Tracks token usage, detects failures/gutter, writes to .ralph/ logs.
#
# Usage:
#   cursor-agent -p --force --output-format stream-json "..." | ./stream-parser.sh /path/to/workspace
#
# Outputs to stdout:
#   - ROTATE when threshold hit (80k tokens)
#   - WARN when approaching limit (70k tokens)
#   - GUTTER when stuck pattern detected
#   - COMPLETE when agent outputs <ralph>COMPLETE</ralph>
#
# Writes to .ralph/:
#   - activity.log: all operations with context health
#   - errors.log: failures and gutter detection

set -euo pipefail

WORKSPACE="${1:-.}"
RALPH_DIR="$WORKSPACE/.ralph"

# Ensure .ralph directory exists
mkdir -p "$RALPH_DIR"

# Dependencies check
if ! command -v jq >/dev/null 2>&1; then
  echo "[$(date '+%H:%M:%S')] ERROR: jq not found; stream parsing disabled." >> "$RALPH_DIR/errors.log"
  # Consume stdin to avoid blocking and exit gracefully
  cat >/dev/null
  exit 1
fi
if ! command -v bc >/dev/null 2>&1; then
  echo "[$(date '+%H:%M:%S')] WARN: bc not found; using integer math for KB estimates." >> "$RALPH_DIR/errors.log"
fi

# Thresholds
WARN_THRESHOLD=70000
ROTATE_THRESHOLD=80000

# Tracking state
BYTES_READ=0
BYTES_WRITTEN=0
ASSISTANT_CHARS=0
SHELL_OUTPUT_CHARS=0
PROMPT_CHARS=0
TOOL_CALLS=0
WARN_SENT=0

# Estimate initial prompt size (Ralph prompt is ~2KB + file references)
PROMPT_CHARS=3000

# Gutter detection - use temp files instead of associative arrays (macOS bash 3.x compat)
FAILURES_FILE=$(mktemp)
WRITES_FILE=$(mktemp)
trap "rm -f $FAILURES_FILE $WRITES_FILE" EXIT

# Get context health emoji
get_health_emoji() {
  local tokens=$1
  local pct=$((tokens * 100 / ROTATE_THRESHOLD))

  if [[ $pct -lt 60 ]]; then
    echo "🟢"
  elif [[ $pct -lt 80 ]]; then
    echo "🟡"
  else
    echo "🔴"
  fi
}

calc_tokens() {
  local total_bytes=$((PROMPT_CHARS + BYTES_READ + BYTES_WRITTEN + ASSISTANT_CHARS + SHELL_OUTPUT_CHARS))
  echo $((total_bytes / 4))
}

# Log to activity.log
log_activity() {
  local message="$1"
  local timestamp=$(date '+%H:%M:%S')
  local tokens=$(calc_tokens)
  local emoji=$(get_health_emoji $tokens)

  echo "[$timestamp] $emoji $message" >> "$RALPH_DIR/activity.log"
  # Mirror to terminal (stderr) without interfering with stdout signals
  printf "\r\033[K[%s] %s %s\n" "$timestamp" "$emoji" "$message" >&2
}

# Log to errors.log
log_error() {
  local message="$1"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] $message" >> "$RALPH_DIR/errors.log"
  printf "\r\033[K[%s] ❗ %s\n" "$timestamp" "$message" >&2
}

# Check and log token status
log_token_status() {
  local tokens=$(calc_tokens)
  local pct=$((tokens * 100 / ROTATE_THRESHOLD))
  local emoji=$(get_health_emoji $tokens)
  local timestamp=$(date '+%H:%M:%S')

  local status_msg="TOKENS: $tokens / $ROTATE_THRESHOLD ($pct%)"

  if [[ $pct -ge 90 ]]; then
    status_msg="$status_msg - rotation imminent"
  elif [[ $pct -ge 72 ]]; then
    status_msg="$status_msg - approaching limit"
  fi

  local breakdown="[read:$((BYTES_READ/1024))KB write:$((BYTES_WRITTEN/1024))KB assist:$((ASSISTANT_CHARS/1024))KB shell:$((SHELL_OUTPUT_CHARS/1024))KB]"
  echo "[$timestamp] $emoji $status_msg $breakdown" >> "$RALPH_DIR/activity.log"
  printf "\r\033[K[%s] %s %s %s\n" "$timestamp" "$emoji" "$status_msg" "$breakdown" >&2
}

# Check for gutter conditions
check_gutter() {
  local tokens=$(calc_tokens)

  # Check rotation threshold
  if [[ $tokens -ge $ROTATE_THRESHOLD ]]; then
    log_activity "ROTATE: Token threshold reached ($tokens >= $ROTATE_THRESHOLD)"
    echo "ROTATE" 2>/dev/null || true
    return
  fi

  # Check warning threshold (only emit once per session)
  if [[ $tokens -ge $WARN_THRESHOLD ]] && [[ $WARN_SENT -eq 0 ]]; then
    log_activity "WARN: Approaching token limit ($tokens >= $WARN_THRESHOLD)"
    WARN_SENT=1
    echo "WARN" 2>/dev/null || true
  fi
}

# Track shell command failure
track_shell_failure() {
  local cmd="$1"
  local exit_code="$2"

  if [[ $exit_code -ne 0 ]]; then
    # Count failures for this command (grep -c exits 1 if no match, so use || true)
    local count
    count=$(grep -c "^${cmd}$" "$FAILURES_FILE" 2>/dev/null) || count=0
    count=$((count + 1))
    echo "$cmd" >> "$FAILURES_FILE"

    log_error "SHELL FAIL: $cmd → exit $exit_code (attempt $count)"

    if [[ $count -ge 3 ]]; then
      log_error "⚠️ GUTTER: same command failed ${count}x"
      echo "GUTTER" 2>/dev/null || true
    fi
  fi
}

# Track file writes for thrashing detection
track_file_write() {
  local path="$1"
  local now=$(date +%s)

  # Log write with timestamp
  echo "$now:$path" >> "$WRITES_FILE"

  # Count writes to this file in last 10 minutes
  local cutoff=$((now - 600))
  local count=$(awk -F: -v cutoff="$cutoff" -v path="$path" '
    $1 >= cutoff && $2 == path { count++ }
    END { print count+0 }
  ' "$WRITES_FILE")

  # Check for thrashing (5+ writes in 10 minutes)
  if [[ $count -ge 5 ]]; then
    log_error "⚠️ THRASHING: $path written ${count}x in 10 min"
    echo "GUTTER" 2>/dev/null || true
  fi
}

# Process a single JSON line from stream
process_line() {
  local line="$1"

  # Skip empty lines
  [[ -z "$line" ]] && return

  # Parse JSON type
  local type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || return
  local subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null) || true

  case "$type" in
    "system")
      if [[ "$subtype" == "init" ]]; then
        local model=$(echo "$line" | jq -r '.model // .data.model // "unknown"' 2>/dev/null) || model="unknown"
        log_activity "SESSION START: model=$model"
      fi
      ;;

    "assistant")
      # Track assistant message characters
      local text=$(echo "$line" | jq -r '.message.content[0].text // .message.content // .text // empty' 2>/dev/null) || text=""
      if [[ -n "$text" ]]; then
        local chars=${#text}
        ASSISTANT_CHARS=$((ASSISTANT_CHARS + chars))

        # Check for completion sigil
        if [[ "$text" == *"<ralph>COMPLETE</ralph>"* ]]; then
          log_activity "✅ Agent signaled COMPLETE"
          echo "COMPLETE" 2>/dev/null || true
        fi

        # Check for gutter sigil
        if [[ "$text" == *"<ralph>GUTTER</ralph>"* ]]; then
          log_activity "🚨 Agent signaled GUTTER (stuck)"
          echo "GUTTER" 2>/dev/null || true
        fi
      fi
      ;;

    "thinking")
      local text=$(echo "$line" | jq -r '.text // .message.content // empty' 2>/dev/null) || text=""
      if [[ -n "$text" ]]; then
        ASSISTANT_CHARS=$((ASSISTANT_CHARS + ${#text}))
      fi
      ;;


    "tool_call")
      if [[ "$subtype" == "started" ]]; then
        TOOL_CALLS=$((TOOL_CALLS + 1))

      elif [[ "$subtype" == "completed" ]]; then
        # Determine tool name/type
        local tool_name=$(echo "$line" | jq -r '.tool_call.name // .tool_call.type // empty' 2>/dev/null) || tool_name=""
        # Handle Read tool
        if echo "$line" | jq -e '.tool_call.readToolCall or (.tool_call.type=="read") or (.tool_call.name|ascii_downcase=="read")' >/dev/null 2>&1; then
          local path=$(echo "$line" | jq -r '.tool_call.readToolCall.args.path // .tool_call.args.path // "unknown"' 2>/dev/null) || path="unknown"
          local lines=$(echo "$line" | jq -r '.tool_call.readToolCall.result.success.totalLines // .tool_call.result.success.totalLines // 0' 2>/dev/null) || lines=0
          local content_size=$(echo "$line" | jq -r '.tool_call.readToolCall.result.success.contentSize // .tool_call.result.success.contentSize // 0' 2>/dev/null) || content_size=0
          local bytes=0
          if [[ $content_size -gt 0 ]]; then bytes=$content_size; else bytes=$((lines * 100)); fi
          BYTES_READ=$((BYTES_READ + bytes))
          local kb=$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null || echo "$((bytes / 1024))")
          log_activity "READ $path ($lines lines, ~${kb}KB)"

        # Handle Write/Edit tool (editToolCall or writeToolCall or name matches)
        elif echo "$line" | jq -e '.tool_call.editToolCall or .tool_call.writeToolCall or (.tool_call.type=="edit") or (.tool_call.name|ascii_downcase=="edit") or (.tool_call.type=="write") or (.tool_call.name|ascii_downcase=="write")' >/dev/null 2>&1; then
          local path=$(echo "$line" | jq -r '.tool_call.editToolCall.args.path // .tool_call.writeToolCall.args.path // .tool_call.args.path // "unknown"' 2>/dev/null) || path="unknown"
          local content=$(echo "$line" | jq -r '.tool_call.editToolCall.result.success.afterFullFileContent // empty' 2>/dev/null) || content=""
          local bytes=${#content}
          if [[ $bytes -le 0 ]]; then
            local lines=$(echo "$line" | jq -r '.tool_call.editToolCall.result.success.linesAdded // .tool_call.writeToolCall.result.success.linesCreated // 0' 2>/dev/null) || lines=0
            bytes=$((lines * 100))
          fi
          BYTES_WRITTEN=$((BYTES_WRITTEN + bytes))
          local kb=$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null || echo "$((bytes / 1024))")
          log_activity "WRITE $path (~${kb}KB)"
          track_file_write "$path"

        # Handle Shell tool
        elif echo "$line" | jq -e '.tool_call.shellToolCall or (.tool_call.type=="shell") or (.tool_call.name|ascii_downcase=="shell")' >/dev/null 2>&1; then
          local cmd=$(echo "$line" | jq -r '.tool_call.shellToolCall.args.command // .tool_call.args.command // "unknown"' 2>/dev/null) || cmd="unknown"
          local exit_code=$(echo "$line" | jq -r '.tool_call.shellToolCall.result.exitCode // .tool_call.result.exitCode // 0' 2>/dev/null) || exit_code=0
          local stdout=$(echo "$line" | jq -r '.tool_call.shellToolCall.result.stdout // .tool_call.result.stdout // ""' 2>/dev/null) || stdout=""
          local stderr=$(echo "$line" | jq -r '.tool_call.shellToolCall.result.stderr // .tool_call.result.stderr // ""' 2>/dev/null) || stderr=""
          local output_chars=$((${#stdout} + ${#stderr}))
          SHELL_OUTPUT_CHARS=$((SHELL_OUTPUT_CHARS + output_chars))
          if [[ $exit_code -eq 0 ]]; then
            if [[ $output_chars -gt 1024 ]]; then
              log_activity "SHELL $cmd → exit 0 (${output_chars} chars output)"
            else
              log_activity "SHELL $cmd → exit 0"
            fi
          else
            log_activity "SHELL $cmd → exit $exit_code"
            track_shell_failure "$cmd" "$exit_code"
          fi
        else
          # Generic tool fallback
          local tool=$(echo "$line" | jq -r '.tool_call.name // .tool_call.type // "tool"' 2>/dev/null) || tool="tool"
          log_activity "TOOL $tool (completed)"
        fi

        # Check thresholds after each tool call
        check_gutter
      fi
      ;;

    "result")
      local duration=$(echo "$line" | jq -r '.duration_ms // .data.duration_ms // 0' 2>/dev/null) || duration=0
      local tokens=$(calc_tokens)
      log_activity "SESSION END: ${duration}ms, ~$tokens tokens used"
      ;;
  esac
}

# Main loop: read JSON lines from stdin
main() {
  # Initialize activity log for this session
  echo "" >> "$RALPH_DIR/activity.log"
  echo "═══════════════════════════════════════════════════════════════" >> "$RALPH_DIR/activity.log"
  echo "Ralph Session Started: $(date)" >> "$RALPH_DIR/activity.log"
  echo "═══════════════════════════════════════════════════════════════" >> "$RALPH_DIR/activity.log"

  # Track last token log time
  local last_token_log=$(date +%s)

  while IFS= read -r line; do
    process_line "$line"

    # Log token status every 30 seconds
    local now=$(date +%s)
    if [[ $((now - last_token_log)) -ge 30 ]]; then
      log_token_status
      last_token_log=$now
    fi
  done

  # Final token status
  log_token_status
}

main


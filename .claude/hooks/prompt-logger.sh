#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 The Worx Company
# Author: Kurt Vanderwater <kurt@worxco.net>

#
# Function: prompt-logger
# Purpose: Automated prompt logging for ISO 27001 audit trail
# Parameters: Hook event name ($1), stdin for event data
# Returns: 0 on success
# Dependencies: jq, date
# Created: 2026-01-28
#

set -euo pipefail

# Configuration
DEVELOPER_INITIALS="KV"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROMPT_LOGS_DIR="${PROJECT_DIR}/PROMPT_LOGS"
SESSION_LOG_FILE="${PROMPT_LOGS_DIR}/.current_session"

# Ensure logs directory exists
mkdir -p "$PROMPT_LOGS_DIR"

# Generate filename based on WorxCo naming convention
generate_filename() {
  local date_str=$(date +%Y%m%d)
  local week_str="WK$(date +%V)"
  local time_str=$(date +%H%M%S)
  echo "${date_str}-${week_str}-${time_str}-${DEVELOPER_INITIALS}.md"
}

# Get or create session log file path
get_session_log() {
  if [ -f "$SESSION_LOG_FILE" ]; then
    cat "$SESSION_LOG_FILE"
  else
    local filename=$(generate_filename)
    local filepath="${PROMPT_LOGS_DIR}/${filename}"
    echo "$filepath" > "$SESSION_LOG_FILE"
    echo "$filepath"
  fi
}

# Initialize a new log file with header
init_log_file() {
  local log_file="$1"
  local project_name=$(basename "$PROJECT_DIR")
  local git_branch=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "N/A")

  cat > "$log_file" << EOF
# AI Prompt Log

**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Week**: $(date +%V)
**AI System**: Claude Opus 4.5
**Project**: ${project_name}

---

## Metadata

- Developer: ${DEVELOPER_INITIALS}
- User: $(whoami)
- Host: $(hostname)
- PWD: ${PROJECT_DIR}
- Git Branch: ${git_branch}

---

## Session Log

EOF
}

# Append entry to log
append_log() {
  local log_file="$1"
  local event_type="$2"
  local content="$3"
  local timestamp=$(date '+%H:%M:%S')

  echo "### ${timestamp} - ${event_type}" >> "$log_file"
  echo "" >> "$log_file"
  echo "$content" >> "$log_file"
  echo "" >> "$log_file"
  echo "---" >> "$log_file"
  echo "" >> "$log_file"
}

# Read event data from stdin (JSON format from Claude Code)
read_event_data() {
  if [ -t 0 ]; then
    echo "{}"
  else
    cat
  fi
}

# Main hook handler
main() {
  local hook_event="${1:-unknown}"
  local event_data=$(read_event_data)
  local log_file=$(get_session_log)

  case "$hook_event" in
    "SessionStart")
      # Create new log file for session
      rm -f "$SESSION_LOG_FILE"
      log_file=$(get_session_log)
      init_log_file "$log_file"
      append_log "$log_file" "Session Started" "New Claude Code session initialized."
      ;;

    "UserPromptSubmit")
      # Log user prompt
      if [ ! -f "$log_file" ]; then
        init_log_file "$log_file"
      fi
      local prompt=$(echo "$event_data" | jq -r '.prompt // "No prompt captured"' 2>/dev/null || echo "No prompt captured")
      append_log "$log_file" "User Prompt" "\`\`\`\n${prompt}\n\`\`\`"
      ;;

    "PostToolUse")
      # Log file modifications
      if [ ! -f "$log_file" ]; then
        init_log_file "$log_file"
      fi
      local tool_name=$(echo "$event_data" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
      local tool_input=$(echo "$event_data" | jq -r '.tool_input.file_path // .tool_input.command // "N/A"' 2>/dev/null || echo "N/A")

      if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" ]]; then
        append_log "$log_file" "File Modified ($tool_name)" "- \`${tool_input}\`"
      fi
      ;;

    "Stop")
      # Log response completion
      if [ ! -f "$log_file" ]; then
        init_log_file "$log_file"
      fi
      local stop_reason=$(echo "$event_data" | jq -r '.stop_reason // "completed"' 2>/dev/null || echo "completed")
      append_log "$log_file" "Response Complete" "Stop reason: ${stop_reason}"
      ;;

    "SessionEnd")
      # Finalize log
      if [ -f "$log_file" ]; then
        append_log "$log_file" "Session Ended" "Session closed."
        echo "" >> "$log_file"
        echo "---" >> "$log_file"
        echo "" >> "$log_file"
        echo "<sub>**License:** GPL-2.0-or-later | **Copyright:** 2026 The Worx Company | **Author:** Kurt Vanderwater <<kurt@worxco.net>></sub>" >> "$log_file"
      fi
      rm -f "$SESSION_LOG_FILE"
      ;;

    *)
      # Unknown event - log anyway
      if [ -f "$log_file" ]; then
        append_log "$log_file" "Unknown Event: $hook_event" "Event data: $(echo "$event_data" | head -c 500)"
      fi
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_build_finalize_prompt(){
  local session_file="$1"
  local transcript_file="$2"
  local out; out="$(ai_mktemp)"

  sed -e "s|{{SESSION_FILE}}|$session_file|g" \
      -e "s|{{TRANSCRIPT_FILE}}|$transcript_file|g" \
      "${AICTX_HOME}/templates/FINALIZE_PROMPT.md" > "$out"

  echo "$out"
}

aictx_build_prompt(){
  local session_file="$1"
  local prev_session="$2"
  local mode="${3:-paths}"
  local out; out="$(ai_mktemp)"

  if [[ "$mode" == "inline" ]]; then
    {
      echo "# aictx inline"
      cat "$AICTX_DIR/PROMPT.md"
      echo "## DIGEST.md"
      cat "$AICTX_DIGEST_FILE" 2>/dev/null || true
      echo "## CONTEXT.md"
      cat "$AICTX_DIR/CONTEXT.md"
      echo "## DECISIONS.md"
      cat "$AICTX_DIR/DECISIONS.md"
      echo "## TODO.md"
      cat "$AICTX_DIR/TODO.md"
      if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
        echo "## Previous session"
        cat "$prev_session"
      fi
      echo "## Session file to update"
      echo "$session_file"
    } > "$out"
  else
    local prev_note=""
    if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
      prev_note=" $prev_session"
    fi
    {
      echo "# aictx paths"
      echo "Read: $AICTX_DIR/PROMPT.md; $AICTX_DIGEST_FILE (first). Optional: $AICTX_DIR/CONTEXT.md $AICTX_DIR/DECISIONS.md $AICTX_DIR/TODO.md$prev_note"
      echo "Update session file: $session_file"
    } > "$out"
  fi

  echo "$out"
}

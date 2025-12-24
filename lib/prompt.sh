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
      echo "# Project Context (aictx — inline mode)"
      echo
      cat "$AICTX_DIR/PROMPT.md"
      echo
      echo "## DIGEST.md"
      cat "$AICTX_DIGEST_FILE" 2>/dev/null || true
      echo
      echo "## CONTEXT.md"
      cat "$AICTX_DIR/CONTEXT.md"
      echo
      echo "## DECISIONS.md"
      cat "$AICTX_DIR/DECISIONS.md"
      echo
      echo "## TODO.md"
      cat "$AICTX_DIR/TODO.md"
      echo
      if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
        echo "## Previous session"
        cat "$prev_session"
        echo
      fi
      echo "## Active session file (must be updated by end)"
      echo "$session_file"
      echo
      echo "Start by reading files. Work normally."
    } > "$out"
  else
    {
      echo "# aictx — paths mode"
      echo
      echo "Read from disk (no pastes):"
      echo "- $AICTX_DIR/PROMPT.md (instructions)"
      echo "- $AICTX_DIGEST_FILE (working memory, read FIRST)"
      echo
      echo "If needed:"
      echo "- $AICTX_DIR/CONTEXT.md, DECISIONS.md, TODO.md"
      if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
        echo "- $prev_session"
      fi
      echo
      echo "Update at end: $session_file"
    } > "$out"
  fi

  echo "$out"
}

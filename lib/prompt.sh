#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

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
      echo "# aictx — token-optimized context"
      echo
      echo "You have filesystem access to the project."
      echo "Do NOT ask to paste files; read them from disk."
      echo
      echo "1) Read and obey:"
      echo "   - $AICTX_DIR/PROMPT.md"
      echo
      echo "2) Read compact memory first:"
      echo "   - $AICTX_DIGEST_FILE"
      echo
      echo "3) If needed, consult:"
      echo "   - $AICTX_DIR/CONTEXT.md"
      echo "   - $AICTX_DIR/DECISIONS.md"
      echo "   - $AICTX_DIR/TODO.md"
      if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
        echo "   - $prev_session"
      fi
      echo
      echo "4) Update at the end:"
      echo "   - $session_file"
      echo
      echo "Rules:"
      echo "- Do not invent facts; if uncertain, write 'Unknown'."
      echo "- Prefer updating DIGEST.md rather than expanding other files."
      echo "- Keep changes minimal and correct."
      echo
      echo "Begin."
    } > "$out"
  fi

  echo "$out"
}

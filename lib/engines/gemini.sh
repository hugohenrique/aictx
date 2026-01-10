#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=../prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"

aictx_gemini_run(){
  local model="$1" transcript="$2"
  # Gemini CLI loads project instructions from repo-root GEMINI.md automatically.
  # Create GEMINI.md only when using gemini engine.
  [[ -f "$AICTX_ROOT/GEMINI.md" ]] || cp "$AICTX_HOME/templates/GEMINI.md" "$AICTX_ROOT/GEMINI.md"
  run_with_script_transcript "$transcript" gemini --model "$model"
}

aictx_gemini_finalize(){
  local model="$1" session="$2" transcript="$3"

  ai_cmd git || { ai_log "git not found; skipping gemini auto-apply"; return 0; }
  git -C "$AICTX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { ai_log "not a git repo; skipping"; return 0; }

  local patch finalize_prompt
  patch="$AICTX_DIR/finalizer_$(date +"%Y-%m-%d_%H-%M").diff"
  finalize_prompt="$(aictx_build_finalize_prompt "$session" "$transcript")"

  gemini --model "$model" -p "$(cat "$finalize_prompt")" > "$patch"
  rm -f "$finalize_prompt"

  [[ -s "$patch" ]] || { ai_log "empty patch; keeping $patch"; return 0; }
  if git -C "$AICTX_ROOT" apply --whitespace=nowarn "$patch"; then
    rm -f "$patch"
  else
    ai_log "patch failed, kept: $patch"
  fi
}

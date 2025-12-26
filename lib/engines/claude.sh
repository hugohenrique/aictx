#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=../prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"

aictx_claude_run(){
  local model="$1" prompt_file="$2" transcript="$3"
  run_with_script_transcript "$transcript" claude --model "$model" "$(cat "$prompt_file")"
}

aictx_claude_finalize(){
  local model="$1" session="$2" transcript="$3"

  ai_cmd git || { ai_log "git not found; skipping claude auto-apply"; return 0; }
  git -C "$AICTX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { ai_log "not a git repo; skipping"; return 0; }

  local patch finalize_prompt
  patch="$AICTX_DIR/finalizer_$(date +"%Y-%m-%d_%H-%M").diff"
  finalize_prompt="$(aictx_build_finalize_prompt "$session" "$transcript")"

  claude -p --model "$model" "$(cat "$finalize_prompt")" > "$patch"
  rm -f "$finalize_prompt"

  [[ -s "$patch" ]] || { ai_log "empty patch; keeping $patch"; return 0; }
  if git -C "$AICTX_ROOT" apply --whitespace=nowarn "$patch"; then
    rm -f "$patch"
  else
    ai_log "patch failed, kept: $patch"
  fi
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=../prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"

aictx_codex_run(){
  local model="$1" prompt_file="$2" transcript="$3"
  run_with_script_transcript "$transcript" codex --cd "$AICTX_ROOT" --model "$model" --full-auto "$(cat "$prompt_file")"
}

aictx_codex_finalize(){
  local model="$1" session="$2" transcript="$3"
  local finalize_prompt
  finalize_prompt="$(aictx_build_finalize_prompt "$session" "$transcript")"

  codex exec --cd "$AICTX_ROOT" --model "$model" --full-auto "You're the session finalizer.

$(cat "$finalize_prompt")

Now perform the updates directly in the repository files (not as patch, but direct edits)."
  rm -f "$finalize_prompt"
}

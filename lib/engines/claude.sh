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
  aictx_finalize_base "claude" "$model" "$session" "$transcript"
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=../prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"
# shellcheck source=../template.sh
source "${AICTX_HOME}/lib/template.sh"

aictx_gemini_run(){
  local model="$1" transcript="$2"
  # Gemini CLI loads project instructions from repo-root GEMINI.md automatically.
  # Create GEMINI.md only when using gemini engine.
  [[ -f "$AICTX_ROOT/GEMINI.md" ]] || cp "$(aictx_template_path "host" "GEMINI.md")" "$AICTX_ROOT/GEMINI.md"
  run_with_script_transcript "$transcript" gemini --model "$model"
}

aictx_gemini_finalize(){
  local model="$1" session="$2" transcript="$3"
  aictx_finalize_base "gemini" "$model" "$session" "$transcript"
}

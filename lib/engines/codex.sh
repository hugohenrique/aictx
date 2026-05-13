#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=../prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"

aictx_codex_supports_exec(){
  if [[ -n "${AICTX_CODEX_HAS_EXEC:-}" ]]; then
    [[ "$AICTX_CODEX_HAS_EXEC" == "1" ]]
    return
  fi

  if codex exec --help >/dev/null 2>&1; then
    export AICTX_CODEX_HAS_EXEC="1"
    return 0
  fi

  export AICTX_CODEX_HAS_EXEC="0"
  return 1
}

aictx_codex_run(){
  local model="$1" prompt_file="$2" transcript="$3"
  if aictx_codex_supports_exec; then
    run_with_script_transcript "$transcript" codex exec --cd "$AICTX_ROOT" --model "$model" --full-auto "$(cat "$prompt_file")"
  else
    # Backward compatibility with older Codex CLIs without `exec`.
    run_with_script_transcript "$transcript" codex --cd "$AICTX_ROOT" --model "$model" --full-auto "$(cat "$prompt_file")"
  fi
}

aictx_codex_finalize(){
  local model="$1" session="$2" transcript="$3"
  local finalize_prompt
  finalize_prompt="$(aictx_build_finalize_prompt "$session" "$transcript")"

  local -a codex_cmd
  if aictx_codex_supports_exec; then
    codex_cmd=(codex exec --cd "$AICTX_ROOT" --model "$model" --full-auto)
  else
    codex_cmd=(codex --cd "$AICTX_ROOT" --model "$model" --full-auto)
  fi

  "${codex_cmd[@]}" "You're the session finalizer.

$(cat "$finalize_prompt")

Now perform the updates directly in the repository files (not as patch, but direct edits)."
  rm -f "$finalize_prompt"
}

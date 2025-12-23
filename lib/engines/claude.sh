#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_claude_run(){
  local model="$1" prompt_file="$2" transcript="$3"
  local sys_append; sys_append="$(cat "$AICTX_DIR/PROMPT.md")"
  run_with_script_transcript "$transcript" claude --model "$model" --append-system-prompt "$sys_append" "$(cat "$prompt_file")"
}

aictx_claude_finalize(){
  local model="$1" session="$2" transcript="$3"

  ai_cmd git || { ai_log "git not found; skipping claude auto-apply"; return 0; }
  git -C "$AICTX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { ai_log "not a git repo; skipping"; return 0; }

  local sys_append patch
  sys_append="$(cat "$AICTX_DIR/PROMPT.md")"
  patch="$AICTX_DIR/finalizer_$(date +"%Y-%m-%d_%H-%M").diff"

  claude -p --model "$model" --append-system-prompt "$sys_append" "Generate a SINGLE unified diff patch (git apply compatible). Output ONLY the diff, no commentary.

Files to update:
- .aictx/DIGEST.md (compact working memory; keep <= ~80 lines; bullets; no fluff)
- .aictx/CONTEXT.md (<= 30 lines; factual & stable only)
- .aictx/DECISIONS.md (append-only, dated)
- .aictx/TODO.md (actionable tasks only)
- $session (fill Objective / What was done / Decisions / Next steps)

Use this transcript as source of truth:
$transcript

Rules:
- Do not invent facts. If uncertain, write 'Unknown'.
- Prefer updating DIGEST.md rather than expanding other files.
- Keep changes minimal and correct." > "$patch"

  [[ -s "$patch" ]] || { ai_log "empty patch; keeping $patch"; return 0; }
  if git -C "$AICTX_ROOT" apply --whitespace=nowarn "$patch"; then
    rm -f "$patch"
  else
    ai_log "patch failed, kept: $patch"
  fi
}

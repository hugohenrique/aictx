#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_codex_run(){
  local model="$1" prompt_file="$2" transcript="$3"
  run_with_script_transcript "$transcript" codex --cd "$AICTX_ROOT" --model "$model" --full-auto "$(cat "$prompt_file")"
}

aictx_codex_finalize(){
  local model="$1" session="$2" transcript="$3"
  codex exec --cd "$AICTX_ROOT" --model "$model" --full-auto "You're the session finalizer.

Update these files in-place:
- .aictx/DIGEST.md (compact working memory; keep <= ~80 lines; bullets; no fluff)
- .aictx/CONTEXT.md (<= 30 lines, factual & stable only)
- .aictx/DECISIONS.md (append-only, dated)
- .aictx/TODO.md (actionable tasks)
- $session (fill Objective / What was done / Decisions / Next steps)

Transcript source of truth:
$transcript

Rules:
- Do not invent facts. If unsure, write 'Unknown'.
- Prefer updating DIGEST.md rather than expanding other files.
Now perform the updates directly in the repository files."
}

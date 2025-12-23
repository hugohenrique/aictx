#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"
# shellcheck source=./finalize.sh
source "${AICTX_HOME}/lib/finalize.sh"
# shellcheck source=./session.sh
source "${AICTX_HOME}/lib/session.sh"

aictx_watch(){
  aictx_paths_init
  aictx_bootstrap
  aictx_load_config

  local interval=20
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="${2:-20}"; shift 2;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

  ai_log "watching pending in: $AICTX_PENDING_DIR (interval=${interval}s)"
  while true; do
    for p in "$AICTX_PENDING_DIR"/*.json; do
      [[ -f "$p" ]] || continue

      local engine model session transcript
      engine="$(grep -E '"engine"' "$p" | head -n1 | sed -E 's/.*"engine"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
      model="$(grep -E '"model"' "$p" | head -n1 | sed -E 's/.*"model"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
      session="$(grep -E '"session"' "$p" | head -n1 | sed -E 's/.*"session"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
      transcript="$(grep -E '"transcript"' "$p" | head -n1 | sed -E 's/.*"transcript"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

      if [[ -f "$transcript" ]]; then
        local s1 s2
        s1="$(wc -c < "$transcript" 2>/dev/null || echo 0)"
        sleep 2
        s2="$(wc -c < "$transcript" 2>/dev/null || echo 0)"
        if [[ "$s1" == "$s2" ]]; then
          ai_log "finalizing pending: $p"
          if aictx_finalize_one "$engine" "$model" "$session" "$transcript"; then
            aictx_pending_mark_done "$p"
          fi
        fi
      fi
    done
    sleep "$interval"
  done
}

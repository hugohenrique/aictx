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

      # Extract all JSON fields in one operation (4x more efficient)
      local engine model session transcript
      local values
      values="$(ai_json_get_multi "$p" "engine model session transcript")"

      # Parse results (newline-separated)
      engine="$(echo "$values" | sed -n '1p')"
      model="$(echo "$values" | sed -n '2p')"
      session="$(echo "$values" | sed -n '3p')"
      transcript="$(echo "$values" | sed -n '4p')"

      # Validate all required fields are present
      if [[ -z "$engine" || -z "$model" || -z "$session" || -z "$transcript" ]]; then
        ai_log "invalid pending file (missing fields): $p"
        continue
      fi

      if [[ -f "$transcript" ]]; then
        # Check if transcript is stable (no modifications for 2 seconds)
        local mtime1 mtime2
        mtime1="$(ai_stat_mtime "$transcript")"
        sleep 2
        mtime2="$(ai_stat_mtime "$transcript")"
        if [[ "$mtime1" == "$mtime2" ]]; then
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

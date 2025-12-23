#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./engines/codex.sh
source "${AICTX_HOME}/lib/engines/codex.sh"
# shellcheck source=./engines/claude.sh
source "${AICTX_HOME}/lib/engines/claude.sh"
# shellcheck source=./engines/gemini.sh
source "${AICTX_HOME}/lib/engines/gemini.sh"

aictx_choose_engine(){
  local requested="$1"
  if [[ "$requested" == "codex" || "$requested" == "claude" || "$requested" == "gemini" ]]; then
    echo "$requested"; return
  fi
  if ai_cmd codex; then echo "codex"
  elif ai_cmd claude; then echo "claude"
  elif ai_cmd gemini; then echo "gemini"
  else echo "none"
  fi
}

aictx_finalize_one(){
  local engine="$1" model="$2" session="$3" transcript="$4"
  [[ -f "$transcript" ]] || { ai_log "missing transcript: $transcript"; return 1; }
  [[ -f "$session" ]] || { ai_log "missing session: $session"; return 1; }

  if [[ "$engine" == "codex" ]]; then
    aictx_codex_finalize "$model" "$session" "$transcript"
  elif [[ "$engine" == "claude" ]]; then
    aictx_claude_finalize "$model" "$session" "$transcript"
  else
    aictx_gemini_finalize "$model" "$session" "$transcript"
  fi
}

aictx_finalize_cmd(){
  aictx_paths_init
  aictx_bootstrap
  aictx_load_config

  local engine="auto" model="" session="" transcript=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--engine) engine="${2:-}"; shift 2;;
      -m|--model) model="${2:-}"; shift 2;;
      -s|--session) session="${2:-}"; shift 2;;
      -t|--transcript) transcript="${2:-}"; shift 2;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

  local eng; eng="$(aictx_choose_engine "$engine")"
  [[ "$eng" != "none" ]] || ai_die "no engine available"

  [[ -n "$model" ]] || {
    if [[ "$eng" == "codex" ]]; then model="$AICTX_CODEX_MODEL"
    elif [[ "$eng" == "claude" ]]; then model="$AICTX_CLAUDE_MODEL"
    else model="$AICTX_GEMINI_MODEL"
    fi
  }
  [[ -n "$session" ]] || session="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"
  [[ -n "$transcript" ]] || transcript="$(ai_latest_file "$AICTX_TRS_DIR" "*.log")"

  aictx_finalize_one "$eng" "$model" "$session" "$transcript"
  ai_log "finalized: $session"
}

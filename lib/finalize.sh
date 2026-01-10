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

  local engine="auto" model="" session="" transcript="" engine_explicit="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--engine) engine="${2:-}"; engine_explicit="1"; shift 2;;
      -m|--model) model="${2:-}"; shift 2;;
      -s|--session) session="${2:-}"; shift 2;;
      -t|--transcript) transcript="${2:-}"; shift 2;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

local inferred_from_model="0"
if [[ -n "$model" && "$engine_explicit" == "0" ]]; then
  local inferred_engine
  inferred_engine="$(aictx_infer_engine_from_model "$model")"
  if [[ "$inferred_engine" != "auto" ]]; then
    engine="$inferred_engine"
    inferred_from_model="1"
  fi
fi

local eng; eng="$(aictx_choose_engine "$engine")"

  [[ "$eng" != "none" ]] || ai_die "no engine available"

if [[ "$inferred_from_model" == "1" ]]; then
  ai_log "engine=$eng (inferred from --model=$model)"
else
  ai_log "engine=$eng"
fi

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

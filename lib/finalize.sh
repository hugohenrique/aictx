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
# shellcheck source=./skill_runtime.sh
source "${AICTX_HOME}/lib/skill_runtime.sh"

aictx_finalize_usage(){
  cat <<EOF
Usage: aictx finalize [options]

Options:
  -e, --engine <auto|codex|claude|gemini>
  -m, --model <name>
  -s, --session <path>
  -t, --transcript <path>
  -h, --help
EOF
}

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
  local engine="$1" model="$2" session="$3" transcript="$4" skills_csv="${5:-}"
  [[ -f "$transcript" ]] || { ai_log "missing transcript: $transcript"; return 1; }
  [[ -f "$session" ]] || { ai_log "missing session: $session"; return 1; }
  export AICTX_ACTIVE_SKILLS="$skills_csv"

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
  local pending_skills="" pending_intent=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) aictx_finalize_usage; return 0;;
      -e|--engine) engine="${2:-}"; engine_explicit="1"; shift 2;;
      -m|--model) model="${2:-}"; shift 2;;
      -s|--session) session="${2:-}"; shift 2;;
      -t|--transcript) transcript="${2:-}"; shift 2;;
      *) ai_die "unknown arg for finalize: $1 (use: aictx finalize --help)" ;;
    esac
  done

  local latest_pending
  latest_pending="$(ai_latest_file "$AICTX_PENDING_DIR" "*.done.json")"
  [[ -z "$latest_pending" ]] && latest_pending="$(ai_latest_file "$AICTX_PENDING_DIR" "*.json")"
  if [[ -n "$latest_pending" ]]; then
    local p_engine p_model p_session p_transcript p_skills p_intent
    local pending_meta
    pending_meta="$(aictx_pending_get_meta "$latest_pending" 2>/dev/null || true)"
    if [[ -n "$pending_meta" ]]; then
      IFS='|' read -r p_engine p_model p_session p_transcript p_skills p_intent <<< "$pending_meta"
      [[ -z "$session" && -n "$p_session" ]] && session="$p_session"
      [[ -z "$transcript" && -n "$p_transcript" ]] && transcript="$p_transcript"
      [[ -z "$model" && -n "$p_model" ]] && model="$p_model"
      if [[ "$engine" == "auto" && -n "$p_engine" ]]; then
        engine="$p_engine"
      fi
      pending_skills="$p_skills"
      pending_intent="$p_intent"
    fi
  fi

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

  export AICTX_RUN_INTENT="$pending_intent"
  [[ -n "$pending_skills" ]] && ai_log "skills=$pending_skills"
  aictx_finalize_one "$eng" "$model" "$session" "$transcript" "$pending_skills"
  ai_log "finalized: $session"
}

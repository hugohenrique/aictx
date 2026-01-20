#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"
# shellcheck source=./session.sh
source "${AICTX_HOME}/lib/session.sh"
# shellcheck source=./prompt.sh
source "${AICTX_HOME}/lib/prompt.sh"
# shellcheck source=./finalize.sh
source "${AICTX_HOME}/lib/finalize.sh"
# shellcheck source=./engines/codex.sh
source "${AICTX_HOME}/lib/engines/codex.sh"
# shellcheck source=./engines/claude.sh
source "${AICTX_HOME}/lib/engines/claude.sh"
# shellcheck source=./engines/gemini.sh
source "${AICTX_HOME}/lib/engines/gemini.sh"

aictx_status(){
  aictx_paths_init
  if [[ ! -d "$AICTX_DIR" && ! -d "$AICTX_LEGACY_DIR" ]]; then
    ai_die "no .aictx/ (or legacy .codex-context/) found in this project. Run: aictx init"
  fi
  echo "root:         $AICTX_ROOT"
  echo "context:      $AICTX_DIR"
  echo "schema:       $(cat "$AICTX_SCHEMA_FILE" 2>/dev/null || echo "?")"
  echo "prompt_mode:  $(grep -E '"prompt_mode"' "$AICTX_CONFIG_FILE" 2>/dev/null | head -n1 || echo "<default paths>")"
  echo "last session: $(ai_latest_file "$AICTX_SESS_DIR" "*.md" || echo "<none>")"
  echo "last log:     $(ai_latest_file "$AICTX_TRS_DIR" "*.log" || echo "<none>")"
  echo "pending:      $(ls "$AICTX_PENDING_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
}

aictx_run(){
  aictx_bootstrap
  aictx_load_config

  local engine="$AICTX_ENGINE" model_override="" no_finalize="0" engine_explicit="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--engine) engine="${2:-}"; engine_explicit="1"; shift 2;;
      -m|--model) model_override="${2:-}"; shift 2;;
      --no-finalize) no_finalize="1"; shift 1;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

local inferred_from_model="0"
if [[ -n "$model_override" && "$engine_explicit" == "0" ]]; then
  local inferred_engine
  inferred_engine="$(aictx_infer_engine_from_model "$model_override")"
  if [[ "$inferred_engine" != "auto" ]]; then
    engine="$inferred_engine"
    inferred_from_model="1"
  fi
fi

local eng; eng="$(aictx_choose_engine "$engine")"

  [[ "$eng" != "none" ]] || ai_die "no engine available (install codex or claude or gemini)"

  local model
  if [[ -n "$model_override" ]]; then model="$model_override"
  else
    if [[ "$eng" == "codex" ]]; then model="$AICTX_CODEX_MODEL"
    elif [[ "$eng" == "claude" ]]; then model="$AICTX_CLAUDE_MODEL"
    else model="$AICTX_GEMINI_MODEL"
    fi
  fi

  local session prev prompt_file
  session="$(aictx_session_pick)"
  prev="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"
  prompt_file="$(aictx_build_prompt "$session" "$prev" "$AICTX_PROMPT_MODE")"

  local ts transcript
  ts="$(date +"%Y-%m-%d_%H-%M")"
  transcript="$AICTX_TRS_DIR/${eng}_$ts.log"

  # Phase 3: snapshot DIGEST before run for delta-based finalize
  aictx_snapshot_digest

  local pending
  pending="$(aictx_pending_create "$eng" "$model" "$session" "$transcript")"
if [[ "$inferred_from_model" == "1" ]]; then
  ai_log "engine=$eng (inferred from --model=$model_override) model=$model prompt_mode=$AICTX_PROMPT_MODE"
else
  ai_log "engine=$eng model=$model prompt_mode=$AICTX_PROMPT_MODE"
fi

  ai_log "session=$session"
  ai_log "transcript=$transcript"
  ai_log "pending=$pending"

  if [[ "$no_finalize" == "0" && "$AICTX_FINALIZE" == "true" ]]; then
    trap 'aictx_finalize_one "'"$eng"'" "'"$model"'" "'"$session"'" "'"$transcript"'" >/dev/null 2>&1; aictx_pending_mark_done "'"$pending"'"' EXIT HUP INT TERM
  fi

  if [[ "$eng" == "codex" ]]; then
    ai_cmd codex || ai_die "codex not in PATH"
    aictx_codex_run "$model" "$prompt_file" "$transcript"
  elif [[ "$eng" == "claude" ]]; then
    ai_cmd claude || ai_die "claude not in PATH"
    aictx_claude_run "$model" "$prompt_file" "$transcript"
  else
    ai_cmd gemini || ai_die "gemini not in PATH"
    aictx_gemini_run "$model" "$transcript"
  fi

  rm -f "$prompt_file" 2>/dev/null || true

  if [[ "$no_finalize" == "1" || "$AICTX_FINALIZE" != "true" ]]; then
    ai_log "finalize skipped; watcher will handle pending later."
  else
    aictx_pending_mark_done "$pending" || ai_log "warning: failed to mark pending as done: $pending"
  fi
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
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
# shellcheck source=./cleanup.sh
source "${AICTX_HOME}/lib/cleanup.sh"
# shellcheck source=./fallback.sh
source "${AICTX_HOME}/lib/fallback.sh"
# shellcheck source=./context_budget.sh
source "${AICTX_HOME}/lib/context_budget.sh"
# shellcheck source=./engines/codex.sh
source "${AICTX_HOME}/lib/engines/codex.sh"
# shellcheck source=./engines/claude.sh
source "${AICTX_HOME}/lib/engines/claude.sh"
# shellcheck source=./engines/gemini.sh
source "${AICTX_HOME}/lib/engines/gemini.sh"

_aictx_runtime_meta_get(){
  local metadata="$1" key="$2" default_value="${3:-}"
  local pair current_key current_value
  IFS=';' read -ra pair <<< "$metadata"
  for pair in "${pair[@]}"; do
    current_key="${pair%%=*}"
    current_value="${pair#*=}"
    if [[ "$current_key" == "$key" ]]; then
      echo "$current_value"
      return
    fi
  done
  echo "$default_value"
}

aictx_runtime_resolve_engine_model(){
  local engine_spec="$1" model_override="$2" engine_explicit="${3:-0}"

  local resolved_engine="$engine_spec"
  if [[ "$resolved_engine" == "auto" ]]; then
    resolved_engine="$AICTX_ENGINE"
  fi

  local inferred_from_model="0"
  if [[ -n "$model_override" && "$engine_explicit" == "0" ]]; then
    local inferred_engine
    inferred_engine="$(aictx_infer_engine_from_model "$model_override")"
    if [[ "$inferred_engine" != "auto" ]]; then
      resolved_engine="$inferred_engine"
      inferred_from_model="1"
    fi
  fi

  local eng
  eng="$(aictx_choose_engine "$resolved_engine")"
  [[ "$eng" != "none" ]] || ai_die "no engine available (install codex or claude or gemini)"

  local model
  if [[ -n "$model_override" ]]; then
    model="$model_override"
  else
    model="$(aictx_runtime_model_for_engine "$eng")"
  fi

  export AICTX_RUNTIME_ENGINE="$eng"
  export AICTX_RUNTIME_MODEL="$model"
  export AICTX_RUNTIME_ENGINE_INFERRED="$inferred_from_model"
}

aictx_runtime_model_for_engine(){
  case "$1" in
    codex) echo "$AICTX_CODEX_MODEL" ;;
    claude) echo "$AICTX_CLAUDE_MODEL" ;;
    gemini) echo "$AICTX_GEMINI_MODEL" ;;
    *) echo "" ;;
  esac
}

aictx_runtime_execute_engine(){
  local engine="$1" model="$2" prompt_file="$3" transcript="$4"
  case "$engine" in
    codex)
      ai_cmd codex || ai_die "codex not in PATH"
      aictx_codex_run "$model" "$prompt_file" "$transcript"
      ;;
    claude)
      ai_cmd claude || ai_die "claude not in PATH"
      aictx_claude_run "$model" "$prompt_file" "$transcript"
      ;;
    gemini)
      ai_cmd gemini || ai_die "gemini not in PATH"
      aictx_gemini_run "$model" "$transcript"
      ;;
    *)
      ai_die "unsupported engine: $engine"
      ;;
  esac
}

aictx_runtime_install_finalize_trap(){
  local eng="$1" model="$2" session="$3" transcript="$4" pending="$5" skills_csv="$6"
  trap 'aictx_finalize_one "'"$eng"'" "'"$model"'" "'"$session"'" "'"$transcript"'" "'"$skills_csv"'" >/dev/null 2>&1; aictx_pending_mark_done "'"$pending"'"' EXIT HUP INT TERM
}

aictx_runtime_execute(){
  local mode="$1" engine_spec="$2" model_override="$3" input_file="$4" metadata="${5:-}"

  local dry_run no_finalize intent active_skills
  dry_run="$(_aictx_runtime_meta_get "$metadata" "dry_run" "0")"
  no_finalize="$(_aictx_runtime_meta_get "$metadata" "no_finalize" "0")"
  intent="$(_aictx_runtime_meta_get "$metadata" "intent" "")"
  active_skills="$(_aictx_runtime_meta_get "$metadata" "active_skills" "")"

  aictx_paths_init
  if [[ "$dry_run" == "1" ]]; then
    [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
    aictx_load_config
  else
    aictx_bootstrap
    aictx_load_config
    if [[ "$mode" == "run" && "${AICTX_AUTO_COMPACT}" == "true" ]]; then
      aictx_cleanup_all
    fi
  fi

  aictx_runtime_resolve_engine_model "$engine_spec" "$model_override" "$(_aictx_runtime_meta_get "$metadata" "engine_explicit" "0")"

  local eng model
  eng="$AICTX_RUNTIME_ENGINE"
  model="$AICTX_RUNTIME_MODEL"

  if [[ "$mode" == "run" && "$dry_run" == "1" ]]; then
    local session_file prev_session now mtime age
    prev_session="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"
    session_file=""
    if [[ -n "$prev_session" ]]; then
      now="$(date +%s)"
      mtime="$(ai_stat_mtime "$prev_session")"
      age=$((now - mtime))
      if [[ "$age" -le "${AICTX_SESSION_REUSE_SECONDS:-7200}" ]]; then
        session_file="$prev_session"
      fi
    fi
    aictx_context_plan "$session_file" "$prev_session" "$AICTX_PROMPT_MODE"
    export AICTX_RUNTIME_SESSION="$session_file"
    export AICTX_RUNTIME_PREV_SESSION="$prev_session"
    return 0
  fi

  if [[ "$mode" != "run" ]]; then
    local handler
    handler="$(_aictx_runtime_meta_get "$metadata" "handler" "")"
    [[ -n "$handler" ]] || ai_die "runtime handler missing for mode=$mode"
    "$handler" "$eng" "$model" "$input_file" "$metadata"
    return $?
  fi

  local session prev
  session="${input_file:-$(aictx_session_pick)}"
  prev="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"

  aictx_context_plan "$session" "$prev" "$AICTX_PROMPT_MODE"

  local prompt_file
  prompt_file="$(aictx_build_prompt "$session" "$prev" "$AICTX_PROMPT_MODE" "$active_skills" "$intent")"

  local ts transcript
  ts="$(date +"%Y-%m-%d_%H-%M")"
  transcript="$AICTX_TRS_DIR/${eng}_$ts.log"

  aictx_snapshot_digest

  local pending
  pending="$(aictx_pending_create "$eng" "$model" "$session" "$transcript" "$active_skills" "$intent")"

  if [[ "$AICTX_RUNTIME_ENGINE_INFERRED" == "1" ]]; then
    ai_log "engine=$eng (inferred from --model=$model_override) model=$model prompt_mode=$AICTX_PROMPT_MODE"
  else
    ai_log "engine=$eng model=$model prompt_mode=$AICTX_PROMPT_MODE"
  fi
  [[ -n "$active_skills" ]] && ai_log "skills=$active_skills"

  ai_log "session=$session"
  ai_log "transcript=$transcript"
  ai_log "pending=$pending"

  local finalize_enabled="0"
  if [[ "$no_finalize" == "0" && "$AICTX_FINALIZE" == "true" ]]; then
    finalize_enabled="1"
    aictx_runtime_install_finalize_trap "$eng" "$model" "$session" "$transcript" "$pending" "$active_skills"
  fi

  local final_engine final_model final_transcript
  final_engine="$eng"
  final_model="$model"
  final_transcript="$transcript"

  aictx_runtime_execute_engine "$final_engine" "$final_model" "$prompt_file" "$final_transcript"

  if aictx_fallback_enabled && aictx_detect_quota_failure "$final_transcript"; then
    local fallback_engine
    fallback_engine="$(aictx_choose_engine "$AICTX_FALLBACK_ENGINE")"
    if [[ "$fallback_engine" != "none" && "$fallback_engine" != "$final_engine" ]]; then
      local fallback_model
      fallback_model="${AICTX_FALLBACK_MODEL:-}"
      [[ -z "$fallback_model" ]] && fallback_model="$(aictx_runtime_model_for_engine "$fallback_engine")"
      local fallback_ts fallback_transcript
      fallback_ts="$(date +"%Y-%m-%d_%H-%M-%S")"
      fallback_transcript="$AICTX_TRS_DIR/${fallback_engine}_$fallback_ts.log"
      ai_log "fallback triggered; rerunning with $fallback_engine/$fallback_model"
      aictx_runtime_execute_engine "$fallback_engine" "$fallback_model" "$prompt_file" "$fallback_transcript"
      final_engine="$fallback_engine"
      final_model="$fallback_model"
      final_transcript="$fallback_transcript"
      aictx_pending_update_engine "$pending" "$final_engine" "$final_model" "$final_transcript" || ai_log "warning: fallback pending update failed: $pending"
      if [[ "$finalize_enabled" == "1" ]]; then
        aictx_runtime_install_finalize_trap "$final_engine" "$final_model" "$session" "$final_transcript" "$pending" "$active_skills"
      fi
      ai_log "fallback complete; engine=$final_engine model=$final_model transcript=$final_transcript"
    fi
  fi

  rm -f "$prompt_file" 2>/dev/null || true

  if [[ "$no_finalize" == "1" || "$AICTX_FINALIZE" != "true" ]]; then
    ai_log "finalize skipped; watcher will handle pending later."
  else
    aictx_pending_mark_done "$pending" || ai_log "warning: failed to mark pending as done: $pending"
  fi

  export AICTX_RUNTIME_FINAL_ENGINE="$final_engine"
  export AICTX_RUNTIME_FINAL_MODEL="$final_model"
  export AICTX_RUNTIME_FINAL_TRANSCRIPT="$final_transcript"
  export AICTX_RUNTIME_SESSION="$session"
  export AICTX_RUNTIME_PREV_SESSION="$prev"
  export AICTX_RUNTIME_PENDING="$pending"
}

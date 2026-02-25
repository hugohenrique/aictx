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
# shellcheck source=./cleanup.sh
source "${AICTX_HOME}/lib/cleanup.sh"
# shellcheck source=./fallback.sh
source "${AICTX_HOME}/lib/fallback.sh"
# shellcheck source=./engines/codex.sh
source "${AICTX_HOME}/lib/engines/codex.sh"
# shellcheck source=./engines/claude.sh
source "${AICTX_HOME}/lib/engines/claude.sh"
# shellcheck source=./engines/gemini.sh
source "${AICTX_HOME}/lib/engines/gemini.sh"
# shellcheck source=./metrics.sh
source "${AICTX_HOME}/lib/metrics.sh"

aictx_status(){
  aictx_paths_init
  if [[ ! -d "$AICTX_DIR" ]]; then
    ai_die "no .aictx/ found in this project. Run: aictx init"
  fi
  echo "root:         $AICTX_ROOT"
  echo "context:      $AICTX_DIR"
  echo "schema:       $(cat "$AICTX_SCHEMA_FILE" 2>/dev/null || echo "?")"
  echo "prompt_mode:  $(grep -E '"prompt_mode"' "$AICTX_CONFIG_FILE" 2>/dev/null | head -n1 || echo "<default paths>")"
  echo "last session: $(ai_latest_file "$AICTX_SESS_DIR" "*.md" || echo "<none>")"
  echo "last log:     $(ai_latest_file "$AICTX_TRS_DIR" "*.log" || echo "<none>")"
  echo "pending:      $(ls "$AICTX_PENDING_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
}

aictx_model_for_engine(){
  case "$1" in
    codex) echo "$AICTX_CODEX_MODEL" ;;
    claude) echo "$AICTX_CLAUDE_MODEL" ;;
    gemini) echo "$AICTX_GEMINI_MODEL" ;;
    *) echo "" ;;
  esac
}

aictx_execute_engine(){
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

aictx_install_finalize_trap(){
  local eng="$1" model="$2" session="$3" transcript="$4" pending="$5"
  trap 'aictx_finalize_one "'"$eng"'" "'"$model"'" "'"$session"'" "'"$transcript"'" >/dev/null 2>&1; aictx_pending_mark_done "'"$pending"'"' EXIT HUP INT TERM
}

aictx_run(){
  local engine="auto" model_override="" no_finalize="0" engine_explicit="0" dry_run="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--engine) engine="${2:-}"; engine_explicit="1"; shift 2;;
      -m|--model) model_override="${2:-}"; shift 2;;
      --no-finalize) no_finalize="1"; shift 1;;
      --dry-run) dry_run="1"; shift 1;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

  if [[ "$dry_run" == "1" ]]; then
    aictx_paths_init
    [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
    aictx_load_config
  else
    aictx_bootstrap
    aictx_load_config
    if [[ "${AICTX_AUTO_CLEANUP}" == "true" ]]; then
      aictx_cleanup_all
    fi
  fi

  if [[ "$engine" == "auto" ]]; then
    engine="$AICTX_ENGINE"
  fi

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
    model="$(aictx_model_for_engine "$eng")"
  fi

  if [[ "$dry_run" == "1" ]]; then
    local predicted session_file prev_session
    predicted="$(aictx_metrics_predict_session_context)"
    IFS='|' read -r session_file prev_session <<< "$predicted"
    [[ "$session_file" == "__NONE__" ]] && session_file=""
    [[ "$prev_session" == "__NONE__" ]] && prev_session=""
    [[ "$session_file" == "__NEW__" ]] && session_file=""

    local dry_rows dry_total_chars dry_tokens_est
    dry_rows="$(aictx_metrics_collect_rows "$AICTX_PROMPT_MODE" "$session_file" "$prev_session")"
    dry_total_chars="$(aictx_metrics_sum_chars "$dry_rows")"
    dry_tokens_est="$(aictx_metrics_tokens_est "$dry_total_chars")"

    echo "DRY RUN: engine execution skipped."
    echo "engine: $eng"
    echo "model: $model"
    aictx_metrics_print_report "$AICTX_PROMPT_MODE" "$dry_rows" "$dry_total_chars" "$dry_tokens_est"
    aictx_metrics_print_warnings "$AICTX_PROMPT_MODE" "$dry_tokens_est"
    aictx_metrics_log_run "$eng" "$model" "$AICTX_PROMPT_MODE" "$dry_total_chars" "$dry_tokens_est"
    return 0
  fi

  local session prev prompt_file
  session="$(aictx_session_pick)"
  prev="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"

  local run_rows run_total_chars run_tokens_est
  run_rows="$(aictx_metrics_collect_rows "$AICTX_PROMPT_MODE" "$session" "$prev")"
  run_total_chars="$(aictx_metrics_sum_chars "$run_rows")"
  run_tokens_est="$(aictx_metrics_tokens_est "$run_total_chars")"
  aictx_metrics_print_warnings "$AICTX_PROMPT_MODE" "$run_tokens_est"

  prompt_file="$(aictx_build_prompt "$session" "$prev" "$AICTX_PROMPT_MODE")"

  local ts transcript
  ts="$(date +"%Y-%m-%d_%H-%M")"
  transcript="$AICTX_TRS_DIR/${eng}_$ts.log"

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

  local finalize_enabled="0"
  if [[ "$no_finalize" == "0" && "$AICTX_FINALIZE" == "true" ]]; then
    finalize_enabled="1"
    aictx_install_finalize_trap "$eng" "$model" "$session" "$transcript" "$pending"
  fi

  local final_engine="$eng"
  local final_model="$model"
  local final_transcript="$transcript"

  aictx_execute_engine "$final_engine" "$final_model" "$prompt_file" "$final_transcript"

  if aictx_fallback_enabled && aictx_detect_quota_failure "$final_transcript"; then
    local fallback_engine
    fallback_engine="$(aictx_choose_engine "$AICTX_FALLBACK_ENGINE")"
    if [[ "$fallback_engine" != "none" && "$fallback_engine" != "$final_engine" ]]; then
      local fallback_model="${AICTX_FALLBACK_MODEL:-}"
      [[ -z "$fallback_model" ]] && fallback_model="$(aictx_model_for_engine "$fallback_engine")"
      local fallback_ts fallback_transcript
      fallback_ts="$(date +"%Y-%m-%d_%H-%M-%S")"
      fallback_transcript="$AICTX_TRS_DIR/${fallback_engine}_$fallback_ts.log"
      ai_log "fallback triggered; rerunning with $fallback_engine/$fallback_model"
      aictx_execute_engine "$fallback_engine" "$fallback_model" "$prompt_file" "$fallback_transcript"
      final_engine="$fallback_engine"
      final_model="$fallback_model"
      final_transcript="$fallback_transcript"
      aictx_pending_update_engine "$pending" "$final_engine" "$final_model" "$final_transcript" || ai_log "warning: fallback pending update failed: $pending"
      if [[ "$finalize_enabled" == "1" ]]; then
        aictx_install_finalize_trap "$final_engine" "$final_model" "$session" "$final_transcript" "$pending"
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

  aictx_metrics_log_run "$final_engine" "$final_model" "$AICTX_PROMPT_MODE" "$run_total_chars" "$run_tokens_est"
}

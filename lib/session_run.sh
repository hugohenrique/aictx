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
# shellcheck source=./metrics.sh
source "${AICTX_HOME}/lib/metrics.sh"
# shellcheck source=./skill_runtime.sh
source "${AICTX_HOME}/lib/skill_runtime.sh"
# shellcheck source=./runtime.sh
source "${AICTX_HOME}/lib/runtime.sh"

aictx_run_usage(){
  cat <<EOF
Usage: aictx run [options]

Options:
  -e, --engine <auto|codex|claude|gemini>
  -m, --model <name>
  --dry-run
  --no-finalize
  --intent <impl|review|tests|release|refactor|debug|finalize|compact>
  --skill <id>
  --skills <id1,id2>
  --no-skill
  -h, --help
EOF
}

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

aictx_run(){
  local engine="auto" model_override="" no_finalize="0" engine_explicit="0" dry_run="0"
  local intent="" skill_single="" skills_multi="" no_skill="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) aictx_run_usage; return 0 ;;
      -e|--engine) engine="${2:-}"; engine_explicit="1"; shift 2 ;;
      -m|--model) model_override="${2:-}"; shift 2 ;;
      --no-finalize) no_finalize="1"; shift 1 ;;
      --dry-run) dry_run="1"; shift 1 ;;
      --intent) intent="${2:-}"; shift 2 ;;
      --skill) skill_single="${2:-}"; shift 2 ;;
      --skills) skills_multi="${2:-}"; shift 2 ;;
      --no-skill) no_skill="1"; shift 1 ;;
      *) ai_die "unknown arg for run: $1 (use: aictx run --help)" ;;
    esac
  done

  aictx_paths_init
  local active_skills
  active_skills="$(aictx_select_skills "$intent" "$skill_single" "$skills_multi" "$no_skill" "run")"
  export AICTX_ACTIVE_SKILLS="$active_skills"
  export AICTX_RUN_INTENT="$intent"

  if [[ "$dry_run" == "1" ]]; then
    local metadata
    metadata="dry_run=1;engine_explicit=$engine_explicit;intent=$intent;active_skills=$active_skills"
    aictx_runtime_execute "run" "$engine" "$model_override" "" "$metadata"

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
    echo "engine: $AICTX_RUNTIME_ENGINE"
    echo "model: $AICTX_RUNTIME_MODEL"
    aictx_metrics_print_report "$AICTX_PROMPT_MODE" "$dry_rows" "$dry_total_chars" "$dry_tokens_est"
    aictx_metrics_print_warnings "$AICTX_PROMPT_MODE" "$dry_tokens_est"
    aictx_metrics_print_memory_hygiene
    aictx_metrics_log_run "$AICTX_RUNTIME_ENGINE" "$AICTX_RUNTIME_MODEL" "$AICTX_PROMPT_MODE" "$dry_total_chars" "$dry_tokens_est"
    return 0
  fi

  local session prev
  session="$(aictx_session_pick)"
  prev="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"

  local run_rows run_total_chars run_tokens_est
  run_rows="$(aictx_metrics_collect_rows "$AICTX_PROMPT_MODE" "$session" "$prev")"
  run_total_chars="$(aictx_metrics_sum_chars "$run_rows")"
  run_tokens_est="$(aictx_metrics_tokens_est "$run_total_chars")"
  aictx_metrics_print_warnings "$AICTX_PROMPT_MODE" "$run_tokens_est"
  aictx_metrics_print_memory_hygiene

  local metadata
  metadata="engine_explicit=$engine_explicit;no_finalize=$no_finalize;intent=$intent;active_skills=$active_skills"
  aictx_runtime_execute "run" "$engine" "$model_override" "$session" "$metadata"

  aictx_metrics_log_run "$AICTX_RUNTIME_FINAL_ENGINE" "$AICTX_RUNTIME_FINAL_MODEL" "$AICTX_PROMPT_MODE" "$run_total_chars" "$run_tokens_est"
}

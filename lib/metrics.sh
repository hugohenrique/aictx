#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"
# shellcheck source=./context_budget.sh
source "${AICTX_HOME}/lib/context_budget.sh"

aictx_metrics_file(){
  echo "$AICTX_DIR/metrics.jsonl"
}

aictx_metrics_chars(){
  local file="$1"
  [[ -f "$file" ]] || { echo 0; return; }
  wc -c < "$file" 2>/dev/null | tr -d ' ' || echo 0
}

aictx_metrics_nonempty_lines(){
  local file="$1"
  [[ -f "$file" ]] || { echo 0; return; }
  grep -cve '^[[:space:]]*$' "$file" 2>/dev/null || echo 0
}

aictx_metrics_tokens_est(){
  local chars="${1:-0}"
  echo $(((chars + 3) / 4))
}

aictx_metrics_budget_warn_threshold(){
  local budget="${AICTX_TOKEN_BUDGET_EST:-2500}"
  local warn_pct="${AICTX_WARN_BUDGET_PCT:-80}"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=2500
  [[ "$warn_pct" =~ ^[0-9]+$ ]] || warn_pct=80
  echo $((budget * warn_pct / 100))
}

aictx_metrics_print_warnings(){
  local prompt_mode="$1" tokens_est="$2"
  local budget="${AICTX_TOKEN_BUDGET_EST:-2500}"
  local warn_threshold
  warn_threshold="$(aictx_metrics_budget_warn_threshold)"

  [[ "$budget" =~ ^[0-9]+$ ]] || budget=2500

  if [[ "$prompt_mode" == "inline" ]]; then
    ai_log "INLINE MODE ENABLED: token usage significantly higher."
  fi

  if [[ "$tokens_est" -ge "$budget" ]]; then
    ai_log "strong warning: token estimate ($tokens_est) reached budget ($budget)."
    ai_log "suggestions: reduce DIGEST and avoid loading optional files unnecessarily."
    ai_log "note: compact/cleanup runs automatically on 'aictx run' when auto_compact=true."
  elif [[ "$tokens_est" -ge "$warn_threshold" ]]; then
    ai_log "warning: token estimate ($tokens_est) reached warning threshold ($warn_threshold/$budget)."
  fi
}

aictx_metrics_print_memory_hygiene(){
  local digest_max="${AICTX_DIGEST_MAX_LINES:-60}"
  local context_max="${AICTX_CONTEXT_MAX_LINES:-20}"
  local decisions_max_chars="${AICTX_DECISIONS_MAX_CHARS:-5000}"
  local todo_max_chars="${AICTX_TODO_MAX_CHARS:-1200}"

  local digest_lines context_lines decisions_chars todo_chars
  digest_lines="$(aictx_metrics_nonempty_lines "$AICTX_DIGEST_FILE")"
  context_lines="$(aictx_metrics_nonempty_lines "$AICTX_DIR/CONTEXT.md")"
  decisions_chars="$(aictx_metrics_chars "$AICTX_DIR/DECISIONS.md")"
  todo_chars="$(aictx_metrics_chars "$AICTX_DIR/TODO.md")"

  if [[ "$digest_lines" -gt "$digest_max" ]]; then
    ai_log "memory warning: DIGEST.md has $digest_lines non-empty lines (target <= $digest_max)."
  fi
  if [[ "$context_lines" -gt "$context_max" ]]; then
    ai_log "memory warning: CONTEXT.md has $context_lines non-empty lines (target <= $context_max)."
  fi
  if [[ "$decisions_chars" -gt "$decisions_max_chars" ]]; then
    ai_log "memory warning: DECISIONS.md has $decisions_chars chars (target <= $decisions_max_chars)."
    ai_log "hint: next 'aictx run' will compact this when auto_compact=true."
  fi
  if [[ "$todo_chars" -gt "$todo_max_chars" ]]; then
    ai_log "memory warning: TODO.md has $todo_chars chars (target <= $todo_max_chars)."
  fi
}

aictx_metrics_predict_session_context(){
  local last now mtime age
  last="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"
  if [[ -z "$last" ]]; then
    echo "__NONE__|__NONE__"
    return
  fi

  now="$(date +%s)"
  mtime="$(ai_stat_mtime "$last")"
  age=$((now - mtime))

  if [[ "$age" -le "${AICTX_SESSION_REUSE_SECONDS:-7200}" ]]; then
    echo "$last|$last"
  else
    echo "__NEW__|$last"
  fi
}

aictx_metrics_collect_rows(){
  local mode="$1" session_file="$2" prev_session="$3"
  local rows=""
  local file chars

  aictx_context_plan "$session_file" "$prev_session" "$mode"

  file="$AICTX_DIR/PROMPT.md"; chars="$(aictx_metrics_chars "$file")"
  rows+="referenced|PROMPT.md|$file|$chars"$'\n'

  file="$AICTX_DIGEST_FILE"; chars="$(aictx_metrics_chars "$file")"
  rows+="referenced|DIGEST.md|$file|$chars"$'\n'

  if [[ "$AICTX_PLAN_LOAD_CONTEXT" == "1" ]]; then
    file="$AICTX_DIR/CONTEXT.md"; chars="$(aictx_metrics_chars "$file")"
    rows+="included|CONTEXT.md|$file|$chars"$'\n'
  fi
  if [[ "$AICTX_PLAN_LOAD_DECISIONS" == "1" ]]; then
    file="$AICTX_DIR/DECISIONS.md"; chars="$(aictx_metrics_chars "$file")"
    rows+="included|DECISIONS.md|$file|$chars"$'\n'
  fi
  if [[ "$AICTX_PLAN_LOAD_TODO" == "1" ]]; then
    file="$AICTX_DIR/TODO.md"; chars="$(aictx_metrics_chars "$file")"
    rows+="included|TODO.md|$file|$chars"$'\n'
  fi
  if [[ "$AICTX_PLAN_LOAD_PREV_SESSION" == "1" && -n "$prev_session" ]]; then
    chars="$(aictx_metrics_chars "$prev_session")"
    rows+="referenced|last_session|$prev_session|$chars"$'\n'
  fi

  echo "$rows"
}

aictx_metrics_sum_chars(){
  local rows="$1"
  local total=0
  local line chars
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    chars="$(echo "$line" | awk -F'|' '{print $4}')"
    total=$((total + chars))
  done <<< "$rows"
  echo "$total"
}

aictx_metrics_previous(){
  local metrics_file
  metrics_file="$(aictx_metrics_file)"
  [[ -f "$metrics_file" ]] || return 1
  local last
  last="$(tail -n 1 "$metrics_file" 2>/dev/null || true)"
  [[ -n "$last" ]] || return 1

  local ts tokens chars
  ts="$(echo "$last" | sed -nE 's/.*"timestamp":"([^"]+)".*/\1/p')"
  tokens="$(echo "$last" | sed -nE 's/.*"tokens_est":([0-9]+).*/\1/p')"
  chars="$(echo "$last" | sed -nE 's/.*"chars_total":([0-9]+).*/\1/p')"
  [[ -n "$tokens" && -n "$chars" ]] || return 1
  echo "${ts:-unknown}|$chars|$tokens"
}

aictx_metrics_print_report(){
  local mode="$1" rows="$2" total_chars="$3" tokens_est="$4"
  echo "prompt_mode: $mode"
  echo "files:"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local how label path chars
    how="$(echo "$line" | awk -F'|' '{print $1}')"
    label="$(echo "$line" | awk -F'|' '{print $2}')"
    path="$(echo "$line" | awk -F'|' '{print $3}')"
    chars="$(echo "$line" | awk -F'|' '{print $4}')"
    echo "  - $how: $label ($chars chars) -> $path"
  done <<< "$rows"
  echo "total_chars: $total_chars"
  echo "tokens_est: $tokens_est"

  local prev
  if prev="$(aictx_metrics_previous)"; then
    local prev_ts prev_chars prev_tokens
    IFS='|' read -r prev_ts prev_chars prev_tokens <<< "$prev"
    local delta_tokens=$((tokens_est - prev_tokens))
    local delta_chars=$((total_chars - prev_chars))
    echo "previous_run: $prev_ts"
    echo "delta_chars: $delta_chars"
    echo "delta_tokens_est: $delta_tokens"
  fi
}

aictx_metrics_log_run(){
  local engine="$1" model="$2" mode="$3" chars_total="$4" tokens_est="$5"
  local metrics_file ns ts
  metrics_file="$(aictx_metrics_file)"
  ns="${AICTX_NAMESPACE:-default}"
  ts="$(date -Iseconds 2>/dev/null || date)"
  mkdir -p "$(dirname "$metrics_file")"

  # Keep JSON single-line and escaped to preserve jsonl validity.
  local esc_engine esc_model esc_mode esc_ns
  esc_engine="$(echo "$engine" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_model="$(echo "$model" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_mode="$(echo "$mode" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_ns="$(echo "$ns" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"

  printf '{"timestamp":"%s","engine":"%s","model":"%s","prompt_mode":"%s","chars_total":%s,"tokens_est":%s,"namespace":"%s"}\n' \
    "$ts" "$esc_engine" "$esc_model" "$esc_mode" "$chars_total" "$tokens_est" "$esc_ns" >> "$metrics_file"
}

aictx_prompt_plan(){
  aictx_paths_init
  [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
  aictx_load_config

  local predicted session_file prev_session
  predicted="$(aictx_metrics_predict_session_context)"
  IFS='|' read -r session_file prev_session <<< "$predicted"
  [[ "$session_file" == "__NONE__" ]] && session_file=""
  [[ "$prev_session" == "__NONE__" ]] && prev_session=""
  [[ "$session_file" == "__NEW__" ]] && session_file=""

  aictx_context_plan "$session_file" "$prev_session" "$AICTX_PROMPT_MODE"
  aictx_context_plan "$session_file" "$prev_session" "$AICTX_PROMPT_MODE" "print"
}

aictx_stats(){
  local explain="0"
  if [[ "${1:-}" == "--explain" ]]; then
    explain="1"
    shift
  fi
  [[ $# -eq 0 ]] || ai_die "unknown arg for stats: $1 (use: aictx stats [--explain])"

  aictx_paths_init
  [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
  aictx_load_config

  local predicted session_file prev_session
  predicted="$(aictx_metrics_predict_session_context)"
  IFS='|' read -r session_file prev_session <<< "$predicted"
  [[ "$session_file" == "__NONE__" ]] && session_file=""
  [[ "$prev_session" == "__NONE__" ]] && prev_session=""
  [[ "$session_file" == "__NEW__" ]] && session_file=""

  local rows total_chars tokens_est
  rows="$(aictx_metrics_collect_rows "$AICTX_PROMPT_MODE" "$session_file" "$prev_session")"
  total_chars="$(aictx_metrics_sum_chars "$rows")"
  tokens_est="$(aictx_metrics_tokens_est "$total_chars")"

  aictx_metrics_print_report "$AICTX_PROMPT_MODE" "$rows" "$total_chars" "$tokens_est"
  if [[ "$explain" == "1" ]]; then
    aictx_context_plan "$session_file" "$prev_session" "$AICTX_PROMPT_MODE"
    aictx_context_explain
  fi
  aictx_metrics_print_warnings "$AICTX_PROMPT_MODE" "$tokens_est"
  aictx_metrics_print_memory_hygiene
}

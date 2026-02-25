#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

AICTX_ENGINE_DEFAULT="auto"
AICTX_CODEX_MODEL_DEFAULT="gpt-5.1-codex-max"
AICTX_CLAUDE_MODEL_DEFAULT="sonnet"
AICTX_GEMINI_MODEL_DEFAULT="auto"
AICTX_SESSION_REUSE_SECONDS_DEFAULT=$((2*60*60))
AICTX_FINALIZE_DEFAULT="true"
AICTX_PROMPT_MODE_DEFAULT="paths" # paths|inline
AICTX_AUTO_CLEANUP_DEFAULT="true"
AICTX_AUTO_COMPACT_DEFAULT="true"
AICTX_AUTO_COMPACT_AI_DEFAULT="false"
AICTX_DECISION_KEEP_DAYS_DEFAULT="30"
AICTX_TRANSCRIPT_KEEP_DAYS_DEFAULT="30"
AICTX_FALLBACK_ENGINE_DEFAULT=""
AICTX_FALLBACK_MODEL_DEFAULT=""
AICTX_FALLBACK_ON_QUOTA_DEFAULT="false"
AICTX_TOKEN_BUDGET_EST_DEFAULT="2500"
AICTX_WARN_BUDGET_PCT_DEFAULT="80"
AICTX_DIGEST_MAX_LINES_DEFAULT="60"
AICTX_CONTEXT_MAX_LINES_DEFAULT="20"
AICTX_DECISIONS_MAX_CHARS_DEFAULT="5000"
AICTX_TODO_MAX_CHARS_DEFAULT="1200"

aictx_json_get(){
  local file="$1" key="$2" def="$3"
  [[ -f "$file" ]] || { echo "$def"; return; }
  local line
  line="$(grep -E "\"$key\"[[:space:]]*:" "$file" | head -n 1 || true)"
  [[ -n "$line" ]] || { echo "$def"; return; }
  line="${line#*:}"
  line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:],]+$//')"
  line="$(echo "$line" | sed -E 's/^"//; s/"$//')"
  echo "${line:-$def}"
}

aictx_load_config(){
  local cfg="$AICTX_CONFIG_FILE"
  export AICTX_ENGINE; AICTX_ENGINE="$(aictx_json_get "$cfg" "engine" "$AICTX_ENGINE_DEFAULT")"
  export AICTX_CODEX_MODEL; AICTX_CODEX_MODEL="$(aictx_json_get "$cfg" "codex_model" "$AICTX_CODEX_MODEL_DEFAULT")"
  export AICTX_CLAUDE_MODEL; AICTX_CLAUDE_MODEL="$(aictx_json_get "$cfg" "claude_model" "$AICTX_CLAUDE_MODEL_DEFAULT")"
  export AICTX_GEMINI_MODEL; AICTX_GEMINI_MODEL="$(aictx_json_get "$cfg" "gemini_model" "$AICTX_GEMINI_MODEL_DEFAULT")"
  export AICTX_SESSION_REUSE_SECONDS; AICTX_SESSION_REUSE_SECONDS="$(aictx_json_get "$cfg" "session_reuse_seconds" "$AICTX_SESSION_REUSE_SECONDS_DEFAULT")"
  export AICTX_FINALIZE; AICTX_FINALIZE="$(aictx_json_get "$cfg" "finalize" "$AICTX_FINALIZE_DEFAULT")"
  export AICTX_PROMPT_MODE; AICTX_PROMPT_MODE="$(aictx_json_get "$cfg" "prompt_mode" "$AICTX_PROMPT_MODE_DEFAULT")"
  export AICTX_AUTO_CLEANUP; AICTX_AUTO_CLEANUP="$(aictx_json_get "$cfg" "auto_cleanup" "$AICTX_AUTO_CLEANUP_DEFAULT")"
  # Keep backward compatibility: if auto_compact is absent, inherit auto_cleanup behavior.
  export AICTX_AUTO_COMPACT; AICTX_AUTO_COMPACT="$(aictx_json_get "$cfg" "auto_compact" "$AICTX_AUTO_CLEANUP")"
  export AICTX_AUTO_COMPACT_AI; AICTX_AUTO_COMPACT_AI="$(aictx_json_get "$cfg" "auto_compact_ai" "$AICTX_AUTO_COMPACT_AI_DEFAULT")"
  export AICTX_DECISION_KEEP_DAYS; AICTX_DECISION_KEEP_DAYS="$(aictx_json_get "$cfg" "decision_keep_days" "$AICTX_DECISION_KEEP_DAYS_DEFAULT")"
  export AICTX_TRANSCRIPT_KEEP_DAYS; AICTX_TRANSCRIPT_KEEP_DAYS="$(aictx_json_get "$cfg" "transcript_keep_days" "$AICTX_TRANSCRIPT_KEEP_DAYS_DEFAULT")"
  local fallback_engine_val
  fallback_engine_val="$(aictx_json_get "$cfg" "fallback_engine" "$AICTX_FALLBACK_ENGINE_DEFAULT")"
  fallback_engine_val="$(echo "$fallback_engine_val" | tr '[:upper:]' '[:lower:]')"
  export AICTX_FALLBACK_ENGINE="$fallback_engine_val"
  export AICTX_FALLBACK_MODEL; AICTX_FALLBACK_MODEL="$(aictx_json_get "$cfg" "fallback_model" "$AICTX_FALLBACK_MODEL_DEFAULT")"
  export AICTX_FALLBACK_ON_QUOTA; AICTX_FALLBACK_ON_QUOTA="$(aictx_json_get "$cfg" "fallback_on_quota" "$AICTX_FALLBACK_ON_QUOTA_DEFAULT")"
  export AICTX_TOKEN_BUDGET_EST; AICTX_TOKEN_BUDGET_EST="$(aictx_json_get "$cfg" "token_budget_est" "$AICTX_TOKEN_BUDGET_EST_DEFAULT")"
  export AICTX_WARN_BUDGET_PCT; AICTX_WARN_BUDGET_PCT="$(aictx_json_get "$cfg" "warn_budget_pct" "$AICTX_WARN_BUDGET_PCT_DEFAULT")"
  export AICTX_DIGEST_MAX_LINES; AICTX_DIGEST_MAX_LINES="$(aictx_json_get "$cfg" "digest_max_lines" "$AICTX_DIGEST_MAX_LINES_DEFAULT")"
  export AICTX_CONTEXT_MAX_LINES; AICTX_CONTEXT_MAX_LINES="$(aictx_json_get "$cfg" "context_max_lines" "$AICTX_CONTEXT_MAX_LINES_DEFAULT")"
  export AICTX_DECISIONS_MAX_CHARS; AICTX_DECISIONS_MAX_CHARS="$(aictx_json_get "$cfg" "decisions_max_chars" "$AICTX_DECISIONS_MAX_CHARS_DEFAULT")"
  export AICTX_TODO_MAX_CHARS; AICTX_TODO_MAX_CHARS="$(aictx_json_get "$cfg" "todo_max_chars" "$AICTX_TODO_MAX_CHARS_DEFAULT")"
}

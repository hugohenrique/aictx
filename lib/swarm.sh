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
# rely on review helpers (aictx_template_fill, aictx_git_context, aictx_review_invoke_engine)

aictx_swarm_pass(){
  local template="$1"
  local output="$2"
  local engine="$3"
  local model="$4"
  shift 4
  local prompt
  prompt="$(ai_mktemp)"
  aictx_template_fill "$template" "$prompt" "$@"
  aictx_review_invoke_engine "$engine" "$model" "$prompt" "$output"
  ai_sanitize_transcript "$output"
  rm -f "$prompt"
}

aictx_swarm(){
  aictx_paths_init
  aictx_bootstrap
  aictx_load_config

  local impl_spec="codex"
  local review_spec="claude"
  local since=""
  local paths=""
  local fix_flag="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --impl) impl_spec="${2:-}"; shift 2;;
      --review) review_spec="${2:-}"; shift 2;;
      --since) since="${2:-}"; shift 2;;
      --paths) paths="${2:-}"; shift 2;;
      --fix) fix_flag="1"; shift 1;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

  local impl_engine review_engine
  impl_engine="$(aictx_choose_engine "${impl_spec:-codex}")"
  [[ "$impl_engine" != "none" ]] || ai_die "no implementation engine available"
  review_engine="$(aictx_choose_engine "${review_spec:-claude}")"
  [[ "$review_engine" != "none" ]] || ai_die "no review engine available"

  local impl_model review_model
  impl_model="$(aictx_model_for_engine "$impl_engine")"
  review_model="$(aictx_model_for_engine "$review_engine")"

  local context_pair git_status git_diff
  context_pair="$(aictx_git_context "$since" "$paths")"
  IFS=$'\037' read -r git_status git_diff <<< "$context_pair"

  local paths_desc since_desc context
  paths_desc="${paths:-all tracked files}"
  since_desc="${since:-<not specified>}"
  context="$(cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true)"

  local impl_output review_output fix_output
  impl_output="$(ai_mktemp)"
  review_output="$(ai_mktemp)"
  fix_output="$(ai_mktemp)"

  aictx_swarm_pass "$AICTX_HOME/templates/SWARM_IMPL_PROMPT.md" "$impl_output" "$impl_engine" "$impl_model" \
    "SINCE=$since_desc" \
    "PATHS=$paths_desc" \
    "GIT_STATUS=$git_status" \
    "GIT_DIFF=$git_diff" \
    "CONTEXT=$context"

  aictx_review_generate_report "$review_engine" "$review_model" "$since" "$paths" "$review_output"

  local fix_section="Fix pass not requested."
  if [[ "$fix_flag" == "1" ]]; then
    aictx_swarm_pass "$AICTX_HOME/templates/SWARM_FIX_PROMPT.md" "$fix_output" "$impl_engine" "$impl_model" \
      "SINCE=$since_desc" \
      "PATHS=$paths_desc" \
      "GIT_STATUS=$git_status" \
      "GIT_DIFF=$git_diff" \
      "IMPLEMENTATION_SUMMARY=$(cat "$impl_output")" \
      "REVIEW_SUMMARY=$(cat "$review_output")"
    fix_section="$(cat "$fix_output")"
  else
    rm -f "$fix_output"
    fix_output=""
  fi

  local namespace="${AICTX_NAMESPACE:-default}"
  namespace="${namespace//[^a-zA-Z0-9._-]/_}"
  local ts
  ts="$(date +"%Y-%m-%d_%H-%M-%S")"
  local swarm_dir="$AICTX_DIR/swarm"
  mkdir -p "$swarm_dir"
  local report="$swarm_dir/${ts}.md"

  {
    printf '# Agent Swarm Report\n'
    printf 'Namespace: %s\n' "$namespace"
    printf 'Timestamp: %s\n' "$ts"
    printf 'Paths: %s\n' "$paths_desc"
    printf 'Since: %s\n\n' "$since_desc"
    printf '## Git status\n%s\n\n' "$git_status"
    printf '## Diff stats\n%s\n\n' "$git_diff"
    printf '## Implementation Pass (%s)\n' "$impl_engine"
    cat "$impl_output"
    printf '\n## Review Pass (%s)\n' "$review_engine"
    cat "$review_output"
    printf '\n## Fix Pass\n%s\n' "$fix_section"
  } > "$report"

  ai_sanitize_transcript "$report"
  rm -f "$impl_output" "$review_output"
  [[ -n "$fix_output" ]] && rm -f "$fix_output"

  ai_log "swarm report saved: $report"
}

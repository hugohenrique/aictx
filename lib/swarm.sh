#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./skill_runtime.sh
source "${AICTX_HOME}/lib/skill_runtime.sh"
# shellcheck source=./template.sh
source "${AICTX_HOME}/lib/template.sh"
# shellcheck source=./runtime.sh
source "${AICTX_HOME}/lib/runtime.sh"
# shellcheck source=./review.sh
source "${AICTX_HOME}/lib/review.sh"

aictx_swarm_usage(){
  cat <<EOF
Usage: aictx swarm [options]

Options:
  --impl <auto|codex|claude|gemini>
  --review <auto|codex|claude|gemini>
  --fix
  --since <git-ref>
  --paths "<path1 path2>"
  --intent <impl|review|tests|release|refactor|debug|finalize|compact>
  --skill <id>
  --skills <id1,id2>
  --no-skill
  -h, --help
EOF
}

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

aictx_swarm_runtime_handler(){
  local impl_engine="$1" impl_model="$2" _input_file="$3" metadata="$4"

  local review_spec since paths fix_flag intent active_skills
  review_spec="$(_aictx_runtime_meta_get "$metadata" "review_spec" "claude")"
  since="$(_aictx_runtime_meta_get "$metadata" "since" "")"
  paths="$(_aictx_runtime_meta_get "$metadata" "paths" "")"
  fix_flag="$(_aictx_runtime_meta_get "$metadata" "fix_flag" "0")"
  intent="$(_aictx_runtime_meta_get "$metadata" "intent" "swarm")"
  active_skills="$(_aictx_runtime_meta_get "$metadata" "active_skills" "")"

  local review_engine
  review_engine="$(aictx_choose_engine "${review_spec:-claude}")"
  [[ "$review_engine" != "none" ]] || ai_die "no review engine available"
  local review_model
  review_model="$(aictx_runtime_model_for_engine "$review_engine")"

  local skill_policy="No active skills."
  if [[ -n "$active_skills" ]]; then
    skill_policy="$(aictx_skills_overlay_block "$active_skills")"
  fi

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

  aictx_swarm_pass "$(aictx_template_path "prompts" "SWARM_IMPL_PROMPT.md")" "$impl_output" "$impl_engine" "$impl_model" \
    "SINCE=$since_desc" \
    "PATHS=$paths_desc" \
    "GIT_STATUS=$git_status" \
    "GIT_DIFF=$git_diff" \
    "CONTEXT=$context" \
    "INTENT=$intent" \
    "ACTIVE_SKILLS=${active_skills:-none}" \
    "SKILL_POLICY=$skill_policy"

  aictx_review_generate_report "$review_engine" "$review_model" "$since" "$paths" "$review_output" "$active_skills"

  local fix_section="Fix pass not requested."
  if [[ "$fix_flag" == "1" ]]; then
    aictx_swarm_pass "$(aictx_template_path "prompts" "SWARM_FIX_PROMPT.md")" "$fix_output" "$impl_engine" "$impl_model" \
      "SINCE=$since_desc" \
      "PATHS=$paths_desc" \
      "GIT_STATUS=$git_status" \
      "GIT_DIFF=$git_diff" \
      "IMPLEMENTATION_SUMMARY=$(cat "$impl_output")" \
      "REVIEW_SUMMARY=$(cat "$review_output")" \
      "INTENT=$intent" \
      "ACTIVE_SKILLS=${active_skills:-none}" \
      "SKILL_POLICY=$skill_policy"
    fix_section="$(cat "$fix_output")"
  else
    rm -f "$fix_output"
    fix_output=""
  fi

  local namespace ts swarm_dir report
  namespace="${AICTX_NAMESPACE:-default}"
  namespace="${namespace//[^a-zA-Z0-9._-]/_}"
  ts="$(date +"%Y-%m-%d_%H-%M-%S")"
  swarm_dir="$AICTX_DIR/swarm"
  mkdir -p "$swarm_dir"
  report="$swarm_dir/${ts}.md"

  {
    printf '# Agent Swarm Report\n'
    printf 'Namespace: %s\n' "$namespace"
    printf 'Timestamp: %s\n' "$ts"
    printf 'Paths: %s\n' "$paths_desc"
    printf 'Since: %s\n\n' "$since_desc"
    printf 'Intent: %s\n' "$intent"
    printf 'Active skills: %s\n\n' "${active_skills:-none}"
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

aictx_swarm(){
  local impl_spec="codex"
  local review_spec="claude"
  local since=""
  local paths=""
  local fix_flag="0"
  local intent="" skill_single="" skills_multi="" no_skill="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) aictx_swarm_usage; return 0 ;;
      --impl) impl_spec="${2:-}"; shift 2 ;;
      --review) review_spec="${2:-}"; shift 2 ;;
      --since) since="${2:-}"; shift 2 ;;
      --paths) paths="${2:-}"; shift 2 ;;
      --fix) fix_flag="1"; shift 1 ;;
      --intent) intent="${2:-}"; shift 2 ;;
      --skill) skill_single="${2:-}"; shift 2 ;;
      --skills) skills_multi="${2:-}"; shift 2 ;;
      --no-skill) no_skill="1"; shift 1 ;;
      *) ai_die "unknown arg for swarm: $1 (use: aictx swarm --help)" ;;
    esac
  done

  local active_skills
  active_skills="$(aictx_select_skills "$intent" "$skill_single" "$skills_multi" "$no_skill" "swarm")"
  export AICTX_ACTIVE_SKILLS="$active_skills"
  [[ -z "$intent" ]] && intent="swarm"

  local metadata
  metadata="handler=aictx_swarm_runtime_handler;review_spec=$review_spec;since=$since;paths=$paths;fix_flag=$fix_flag;intent=$intent;active_skills=$active_skills"
  aictx_runtime_execute "swarm" "${impl_spec:-codex}" "" "" "$metadata"
}

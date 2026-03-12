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
# shellcheck source=./spec.sh
source "${AICTX_HOME}/lib/spec.sh"
# shellcheck source=./runtime.sh
source "${AICTX_HOME}/lib/runtime.sh"

aictx_review_usage(){
  cat <<EOF
Usage: aictx review [options]

Options:
  --engine <auto|codex|claude|gemini>
  --since <git-ref>
  --paths "<path1 path2>"
  --intent <impl|review|tests|release|refactor|debug|finalize|compact>
  --skill <id>
  --skills <id1,id2>
  --no-skill
  --spec <slug>
  -h, --help
EOF
}

aictx_git_context(){
  local since="$1" paths="$2"
  local -a path_array=()
  if [[ -n "$paths" ]]; then
    read -ra path_array <<< "$paths"
  fi
  local status
  status="$(git -C "$AICTX_ROOT" status -sb 2>/dev/null || echo "git status unavailable")"
  local diff="Not requested"
  if [[ -n "$since" ]]; then
    if [[ ${#path_array[@]} -gt 0 ]]; then
      diff="$(git -C "$AICTX_ROOT" diff --stat "$since" -- "${path_array[@]}" 2>/dev/null || echo "diff stat unavailable")"
    else
      diff="$(git -C "$AICTX_ROOT" diff --stat "$since" 2>/dev/null || echo "diff stat unavailable")"
    fi
  fi
  printf '%s\037%s' "$status" "$diff"
}

aictx_review_build_prompt(){
  local since="$1" paths="$2" git_status="$3" git_diff="$4" active_skills="$5" spec_slug="${6:-}"
  local out
  out="$(ai_mktemp)"
  local context
  context="$(cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true)"
  local skill_policy="No active skills."
  [[ -n "$active_skills" ]] && skill_policy="$(aictx_skills_overlay_block "$active_skills")"
  local spec_paths="none"
  local spec_context="No active spec."
  if [[ -n "$spec_slug" ]]; then
    spec_paths="$(aictx_spec_paths_label "$spec_slug")"
    spec_context="$(aictx_spec_inline_block "$spec_slug")"
  fi

  local template
  template="$(aictx_template_path "prompts" "REVIEW_PROMPT.md")"
  aictx_template_fill "$template" "$out" \
    "SINCE=${since:-<not specified>}" \
    "PATHS=${paths:-all tracked files}" \
    "GIT_STATUS=$git_status" \
    "GIT_DIFF=$git_diff" \
    "CONTEXT=$context" \
    "SPEC_SLUG=${spec_slug:-none}" \
    "SPEC_PATHS=$spec_paths" \
    "SPEC_CONTEXT=$spec_context" \
    "ACTIVE_SKILLS=${active_skills:-none}" \
    "SKILL_POLICY=$skill_policy"
  echo "$out"
}

aictx_review_invoke_engine(){
  local engine="$1" model="$2" prompt="$3" output="$4"
  case "$engine" in
    codex)
      ai_cmd codex || ai_die "codex not in PATH"
      codex --cd "$AICTX_ROOT" --model "$model" --full-auto "$(cat "$prompt")" > "$output"
      ;;
    claude)
      ai_cmd claude || ai_die "claude not in PATH"
      claude --model "$model" "$(cat "$prompt")" > "$output"
      ;;
    gemini)
      ai_cmd gemini || ai_die "gemini not in PATH"
      gemini --model "$model" "$(cat "$prompt")" > "$output"
      ;;
    *)
      ai_die "unsupported review engine: $engine"
      ;;
  esac
}

aictx_review_generate_report(){
  local engine="$1"
  local model="$2"
  local since="$3"
  local paths="$4"
  local output="$5"
  local active_skills="$6"
  local spec_slug="${7:-}"

  local context_pair
  context_pair="$(aictx_git_context "$since" "$paths")"
  local git_status git_diff
  IFS=$'\037' read -r git_status git_diff <<< "$context_pair"

  local prompt_file
  prompt_file="$(aictx_review_build_prompt "$since" "$paths" "$git_status" "$git_diff" "$active_skills" "$spec_slug")"

  aictx_review_invoke_engine "$engine" "$model" "$prompt_file" "$output"
  ai_sanitize_transcript "$output"

  rm -f "$prompt_file"
}

aictx_review_runtime_handler(){
  local engine="$1" model="$2" _input_file="$3" metadata="$4"
  local since paths active_skills spec_slug
  since="$(_aictx_runtime_meta_get "$metadata" "since" "")"
  paths="$(_aictx_runtime_meta_get "$metadata" "paths" "")"
  active_skills="$(_aictx_runtime_meta_get "$metadata" "active_skills" "")"
  spec_slug="$(_aictx_runtime_meta_get "$metadata" "spec_slug" "")"

  local ts namespace safe_ns report_dir report_file
  ts="$(date +"%Y-%m-%d_%H-%M-%S")"
  namespace="${AICTX_NAMESPACE:-default}"
  safe_ns="${namespace//[^a-zA-Z0-9._-]/_}"
  report_dir="$AICTX_DIR/reviews"
  mkdir -p "$report_dir"
  report_file="$report_dir/${safe_ns}_${ts}.md"

  aictx_review_generate_report "$engine" "$model" "$since" "$paths" "$report_file" "$active_skills" "$spec_slug"
  ai_log "review saved: $report_file"
}

aictx_review(){
  local requested_engine=""
  local since=""
  local paths=""
  local intent="" skill_single="" skills_multi="" no_skill="0" spec_slug=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) aictx_review_usage; return 0 ;;
      --engine) requested_engine="${2:-}"; shift 2 ;;
      --since) since="${2:-}"; shift 2 ;;
      --paths) paths="${2:-}"; shift 2 ;;
      --intent) intent="${2:-}"; shift 2 ;;
      --skill) skill_single="${2:-}"; shift 2 ;;
      --skills) skills_multi="${2:-}"; shift 2 ;;
      --no-skill) no_skill="1"; shift 1 ;;
      --spec) spec_slug="$(aictx_spec_slug_normalize "${2:-}")"; shift 2 ;;
      *) ai_die "unknown arg for review: $1 (use: aictx review --help)" ;;
    esac
  done

  [[ -z "$spec_slug" ]] || aictx_spec_assert_exists "$spec_slug"
  local active_skills
  active_skills="$(aictx_select_skills "${intent:-review}" "$skill_single" "$skills_multi" "$no_skill" "review")"
  export AICTX_ACTIVE_SKILLS="$active_skills"
  export AICTX_ACTIVE_SPEC="$spec_slug"

  local metadata
  metadata="handler=aictx_review_runtime_handler;since=$since;paths=$paths;active_skills=$active_skills;intent=${intent:-review};spec_slug=$spec_slug"
  aictx_runtime_execute "review" "${requested_engine:-auto}" "" "" "$metadata"
}

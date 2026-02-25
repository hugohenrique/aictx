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

aictx_template_fill(){
  local template="$1"
  local output="$2"
  shift 2
  local env_args=()
  for kv in "$@"; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    env_args+=("__TMPL_${key}=${value}")
  done
  env_args+=("__AICTX_ROOT=$AICTX_ROOT")
  env_args+=("__AICTX_CONTEXT=$(cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true)")

  if command -v python3 >/dev/null 2>&1; then
    env "${env_args[@]}" python3 - "$template" "$output" <<'PY'
import os, sys
from pathlib import Path

template = Path(sys.argv[1]).read_text()
replacements = {k[7:]: v for k, v in os.environ.items() if k.startswith("__TMPL_")}
replacements["ROOT"] = os.environ.get("__AICTX_ROOT", "")
context = os.environ.get("__AICTX_CONTEXT")
if context is not None:
    replacements["CONTEXT"] = context

for key, val in replacements.items():
    template = template.replace(f"{{{{{key}}}}}", val)

Path(sys.argv[2]).write_text(template)
PY
  else
    cat <<EOF > "$output"
$(cat "$template")
EOF
  fi
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
  local since="$1" paths="$2" git_status="$3" git_diff="$4"
  local out
  out="$(ai_mktemp)"
  local context
  context="$(cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true)"
  aictx_template_fill "$AICTX_HOME/templates/REVIEW_PROMPT.md" "$out" \
    "SINCE=${since:-<not specified>}" \
    "PATHS=${paths:-all tracked files}" \
    "GIT_STATUS=$git_status" \
    "GIT_DIFF=$git_diff" \
    "CONTEXT=$context"
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

  local context_pair
  context_pair="$(aictx_git_context "$since" "$paths")"
  local git_status git_diff
  IFS=$'\037' read -r git_status git_diff <<< "$context_pair"

  local prompt_file
  prompt_file="$(aictx_review_build_prompt "$since" "$paths" "$git_status" "$git_diff")"

  aictx_review_invoke_engine "$engine" "$model" "$prompt_file" "$output"
  ai_sanitize_transcript "$output"

  rm -f "$prompt_file"
}

aictx_review(){
  aictx_paths_init
  aictx_bootstrap
  aictx_load_config

  local requested_engine=""
  local since=""
  local paths=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engine) requested_engine="${2:-}"; shift 2;;
      --since) since="${2:-}"; shift 2;;
      --paths) paths="${2:-}"; shift 2;;
      *) ai_die "unknown arg: $1" ;;
    esac
  done

  local eng
  eng="$(aictx_choose_engine "${requested_engine:-$AICTX_ENGINE}")"
  [[ "$eng" != "none" ]] || ai_die "no engine available for review"
  local model
  model="$(aictx_model_for_engine "$eng")"

  local ts namespace safe_ns report_dir report_file
  ts="$(date +"%Y-%m-%d_%H-%M-%S")"
  namespace="${AICTX_NAMESPACE:-default}"
  safe_ns="${namespace//[^a-zA-Z0-9._-]/_}"
  report_dir="$AICTX_DIR/reviews"
  mkdir -p "$report_dir"
  report_file="$report_dir/${safe_ns}_${ts}.md"

  aictx_review_generate_report "$eng" "$model" "$since" "$paths" "$report_file"
  ai_log "review saved: $report_file"
}

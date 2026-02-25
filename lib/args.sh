#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./doctor.sh
source "${AICTX_HOME}/lib/doctor.sh"
# shellcheck source=./session_run.sh
source "${AICTX_HOME}/lib/session_run.sh"
# shellcheck source=./finalize.sh
source "${AICTX_HOME}/lib/finalize.sh"
# shellcheck source=./watch.sh
source "${AICTX_HOME}/lib/watch.sh"
# shellcheck source=./launchd.sh
source "${AICTX_HOME}/lib/launchd.sh"
# shellcheck source=./cleanup.sh
source "${AICTX_HOME}/lib/cleanup.sh"
# shellcheck source=./review.sh
source "${AICTX_HOME}/lib/review.sh"
# shellcheck source=./swarm.sh
source "${AICTX_HOME}/lib/swarm.sh"

GLOBAL_NS_HINT="  --ns <name>     target namespace (sessions/transcripts/pending under .aictx/namespaces/<name>)"

aictx_usage(){
  cat <<EOF
aictx — per-project AI context runner (Codex + Claude + Gemini) with token-optimized context

Commands:
  init                 bootstrap .aictx/
  run                  run interactive session (codex/claude/gemini)
  finalize             finalize latest (or specified) transcript/session
  watch                background worker to finalize pending items
  cleanup              cleanup old sessions & pending artifacts (token optimization)
  status               show context status
  doctor               check dependencies and setup
  install-launchd      install macOS LaunchAgent for background watch
  review               generate a read-only architecture/code quality report
  swarm                run swarm pipeline (implementation + review + optional fix)

Flags (run/finalize):
  -e, --engine  auto|codex|claude|gemini
  -m, --model   override model for selected engine
  --no-finalize do not auto-finalize on exit (still creates pending for watcher)

Global:
${GLOBAL_NS_HINT}

Token optimization:
  - Default prompt_mode is "paths" (minimal prompt that points to files).
  - Set .aictx/config.json: "prompt_mode": "inline" if you want the old behavior.

Model-based routing (when --engine not set):
  --model containing 'codex' -> codex
  --model in {opus,sonnet,haiku} or starting with 'claude' -> claude
  --model starting with 'gemini' -> gemini

Examples:
  aictx init
  aictx run
  aictx run --engine claude --model opus
  aictx run --engine gemini --model auto
  aictx finalize
  aictx watch
  aictx status
EOF
}

aictx_main(){
  local raw_args=("$@")
  local namespace=""
  local filtered=()
  local i=0

  while [[ $i -lt ${#raw_args[@]} ]]; do
    case "${raw_args[i]}" in
      --ns)
        if [[ $((i + 1)) -ge ${#raw_args[@]} ]]; then
          ai_die "--ns requires a namespace name"
        fi
        namespace="${raw_args[i + 1]}"
        i=$((i + 2))
        ;;
      *)
        filtered+=("${raw_args[i]}")
        i=$((i + 1))
        ;;
    esac
  done

  [[ -n "$namespace" ]] && export AICTX_NAMESPACE="$namespace"

  local cmd
  local cmd_args=()
  if [[ ${#filtered[@]} -gt 0 ]]; then
    cmd="${filtered[0]}"
    cmd_args=("${filtered[@]:1}")
  else
    cmd="run"
  fi

  case "$cmd" in
    -h|--help|help) aictx_usage ;;
    init) aictx_init "${cmd_args[@]}" ;;
    run) aictx_run "${cmd_args[@]}" ;;
    finalize) aictx_finalize_cmd "${cmd_args[@]}" ;;
    watch) aictx_watch "${cmd_args[@]}" ;;
    cleanup) aictx_cleanup_all "${cmd_args[@]}" ;;
    status) aictx_status "${cmd_args[@]}" ;;
    doctor) aictx_doctor "${cmd_args[@]}" ;;
    install-launchd) aictx_install_launchd "${cmd_args[@]}" ;;
    review) aictx_review "${cmd_args[@]}" ;;
    swarm) aictx_swarm "${cmd_args[@]}" ;;
    *) aictx_usage; ai_die "unknown command: $cmd" ;;
  esac
}

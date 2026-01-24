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

aictx_usage(){
  cat <<EOF
aictx — per-project AI context runner (Codex + Claude + Gemini) with token-optimized context

Commands:
  init                 bootstrap .aictx/, migrate legacy .codex-context/
  run                  run interactive session (codex/claude/gemini)
  finalize             finalize latest (or specified) transcript/session
  watch                background worker to finalize pending items
  cleanup              cleanup old sessions & pending artifacts (token optimization)
  status               show context status
  doctor               check dependencies and setup
  install-launchd      install macOS LaunchAgent for background watch

Flags (run/finalize):
  -e, --engine  auto|codex|claude|gemini
  -m, --model   override model for selected engine
  --no-finalize do not auto-finalize on exit (still creates pending for watcher)

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
  local cmd="${1:-run}"; shift || true
  case "$cmd" in
    -h|--help|help) aictx_usage ;;
    init) aictx_init "$@" ;;
    run) aictx_run "$@" ;;
    finalize) aictx_finalize_cmd "$@" ;;
    watch) aictx_watch "$@" ;;
    cleanup) aictx_cleanup_all "$@" ;;
    status) aictx_status "$@" ;;
    doctor) aictx_doctor "$@" ;;
    install-launchd) aictx_install_launchd "$@" ;;
    *) aictx_usage; ai_die "unknown command: $cmd" ;;
  esac
}

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
# shellcheck source=./spec.sh
source "${AICTX_HOME}/lib/spec.sh"
# shellcheck source=./swarm.sh
source "${AICTX_HOME}/lib/swarm.sh"
# shellcheck source=./metrics.sh
source "${AICTX_HOME}/lib/metrics.sh"
# shellcheck source=./validate.sh
source "${AICTX_HOME}/lib/validate.sh"
# shellcheck source=./sync.sh
source "${AICTX_HOME}/lib/sync.sh"

GLOBAL_NS_HINT="  --ns <name>     target namespace (sessions/transcripts/pending under .aictx/namespaces/<name>)"

aictx_help_command(){
  local topic="${1:-}"
  case "$topic" in
    ""|all|global) aictx_usage ;;
    constitution) aictx_constitution_usage ;;
    specify) aictx_specify_usage ;;
    analyze) aictx_analyze_usage ;;
    run) aictx_run_usage ;;
    review) aictx_review_usage ;;
    swarm) aictx_swarm_usage ;;
    finalize) aictx_finalize_usage ;;
    validate) echo "Usage: aictx validate [--strict]" ;;
    *)
      aictx_usage
      ai_die "unknown help topic: $topic"
      ;;
  esac
}

aictx_usage(){
  cat <<EOF
aictx — per-project AI context runner (Codex + Claude + Gemini) with token-optimized context

Commands:
  init                 bootstrap .aictx/
  constitution         initialize/repair the local constitution file
  specify              create a spec workspace for a feature
  analyze              validate spec/plan/tasks consistency
  run                  run interactive session (codex/claude/gemini)
  finalize             finalize latest (or specified) transcript/session
  watch                background worker to finalize pending items
  cleanup              cleanup old sessions & pending artifacts (token optimization)
  status               show context status
  doctor               check dependencies and setup
  install-launchd      install macOS LaunchAgent for background watch
  review               generate a read-only architecture/code quality report
  swarm                run swarm pipeline (implementation + review + optional fix)
  validate             validate .aictx structure and limits
  sync                 sync local-first adapters (AGENTS/GEMINI/skills)
  prompt-plan          print current context layer plan
  stats                estimate prompt chars/tokens and compare with previous run (use --explain)

Global flags:
${GLOBAL_NS_HINT}

Run flags:
  -e, --engine  auto|codex|claude|gemini
  -m, --model   override model for selected engine
  --no-finalize do not auto-finalize on exit (still creates pending for watcher)
  --dry-run     run only prompt/token analysis (no engine execution)

Skills flags (run/review/swarm):
  --intent      hint skill intent (impl|review|tests|release|refactor|debug|finalize|compact)
  --skill       activate one skill id
  --skills      activate comma-separated skill ids
  --no-skill    disable skill overlays for this run
  --spec        attach a spec workspace from .aictx/specs/<slug>

Review flags:
  --engine      choose engine for the review pass
  --since       compare from git ref
  --paths       restrict analysis paths (space-separated)
  --spec        attach a spec workspace from .aictx/specs/<slug>

Swarm flags:
  --impl        implementation pass engine (default: codex)
  --review      review pass engine (default: claude)
  --fix         add fix-planning pass
  --since       compare from git ref
  --paths       restrict analysis paths (space-separated)

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
  aictx run --intent review
  aictx run --skills impl,review
  aictx run --no-skill
  aictx run --engine claude --model opus
  aictx constitution
  aictx specify 001-example-feature
  aictx analyze 001-example-feature
  aictx run --spec 001-example-feature --dry-run
  aictx review --engine claude --since main --paths src/
  aictx swarm --impl codex --review claude --fix
  aictx validate --strict
  aictx sync
  aictx prompt-plan
  aictx stats --explain
  aictx finalize
  aictx watch
  aictx status

Help:
  aictx help run
  aictx run --help
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
    if [[ ${#filtered[@]} -gt 1 ]]; then
      cmd_args=("${filtered[@]:1}")
    fi
  else
    cmd="run"
  fi

  case "$cmd" in
    -h|--help) aictx_usage ;;
    help) aictx_help_command "${cmd_args[0]:-}" ;;
    init) aictx_init ${cmd_args[@]+"${cmd_args[@]}"} ;;
    run) aictx_run ${cmd_args[@]+"${cmd_args[@]}"} ;;
    finalize) aictx_finalize_cmd ${cmd_args[@]+"${cmd_args[@]}"} ;;
    watch) aictx_watch ${cmd_args[@]+"${cmd_args[@]}"} ;;
    cleanup) aictx_cleanup_all ${cmd_args[@]+"${cmd_args[@]}"} ;;
    status) aictx_status ${cmd_args[@]+"${cmd_args[@]}"} ;;
    doctor) aictx_doctor ${cmd_args[@]+"${cmd_args[@]}"} ;;
    stats) aictx_stats ${cmd_args[@]+"${cmd_args[@]}"} ;;
    prompt-plan) aictx_prompt_plan ${cmd_args[@]+"${cmd_args[@]}"} ;;
    validate) aictx_validate ${cmd_args[@]+"${cmd_args[@]}"} ;;
    sync) aictx_sync ${cmd_args[@]+"${cmd_args[@]}"} ;;
    install-launchd) aictx_install_launchd ${cmd_args[@]+"${cmd_args[@]}"} ;;
    constitution) aictx_constitution ${cmd_args[@]+"${cmd_args[@]}"} ;;
    specify) aictx_specify ${cmd_args[@]+"${cmd_args[@]}"} ;;
    analyze) aictx_analyze ${cmd_args[@]+"${cmd_args[@]}"} ;;
    review) aictx_review ${cmd_args[@]+"${cmd_args[@]}"} ;;
    spec) aictx_spec ${cmd_args[@]+"${cmd_args[@]}"} ;;
    swarm) aictx_swarm ${cmd_args[@]+"${cmd_args[@]}"} ;;
    *) aictx_usage; ai_die "unknown command: $cmd" ;;
  esac
}

#!/usr/bin/env bash
set -euo pipefail

ai_die(){ echo "aictx: $*" >&2; exit 1; }
ai_log(){ echo "aictx: $*" >&2; }

ai_is_macos(){ [[ "$(uname -s)" == "Darwin" ]]; }
ai_cmd(){ command -v "$1" >/dev/null 2>&1; }

ai_project_root(){
  if ai_cmd git && git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

ai_mktemp(){
  if ai_is_macos; then mktemp -t aictx.XXXXXX
  else mktemp
  fi
}

ai_stat_mtime(){
  local f="$1"
  if ai_is_macos; then stat -f %m "$f" 2>/dev/null || echo 0
  else stat -c %Y "$f" 2>/dev/null || echo 0
  fi
}

ai_latest_file(){
  local dir="$1" pattern="$2"
  ls -t "$dir"/$pattern 2>/dev/null | head -n 1 || true
}

run_with_script_transcript() {
  local transcript="$1"; shift
  if ai_is_macos; then
    script -q "$transcript" "$@"
  else
    if script -q "$transcript" "$@" >/dev/null 2>&1; then :; else
      script -q -c "$(printf '%q ' "$@")" "$transcript"
    fi
  fi
}

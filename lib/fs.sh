#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

AICTX_DIR_NAME=".aictx"

aictx_paths_init(){
  export AICTX_ROOT; AICTX_ROOT="$(ai_project_root)"
  export AICTX_DIR; AICTX_DIR="$AICTX_ROOT/$AICTX_DIR_NAME"
  export AICTX_SESS_DIR; AICTX_SESS_DIR="$AICTX_DIR/sessions"
  export AICTX_TRS_DIR; AICTX_TRS_DIR="$AICTX_DIR/transcripts"
  export AICTX_PENDING_DIR; AICTX_PENDING_DIR="$AICTX_DIR/pending"
  export AICTX_GITIGNORE; AICTX_GITIGNORE="$AICTX_ROOT/.gitignore"
  export AICTX_SCHEMA_FILE; AICTX_SCHEMA_FILE="$AICTX_DIR/.schema_version"
  export AICTX_INIT_MARK; AICTX_INIT_MARK="$AICTX_DIR/.initialized"
  export AICTX_DIGEST_FILE; AICTX_DIGEST_FILE="$AICTX_DIR/DIGEST.md"
  export AICTX_CONFIG_FILE; AICTX_CONFIG_FILE="$AICTX_DIR/config.json"
}

aictx_ensure_line_once(){
  local line="$1" file="$2"
  [[ -f "$file" ]] || touch "$file"
  grep -qxF "$line" "$file" || printf "\n%s\n" "$line" >> "$file"
}

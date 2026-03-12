#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./ns.sh
source "${AICTX_HOME}/lib/ns.sh"

AICTX_DIR_NAME=".aictx"

aictx_paths_init(){
  export AICTX_ROOT; AICTX_ROOT="$(ai_project_root)"
  export AICTX_DIR; AICTX_DIR="$AICTX_ROOT/$AICTX_DIR_NAME"
  export AICTX_NAMESPACE="${AICTX_NAMESPACE:-}"
  export AICTX_NAMESPACE_DIR; AICTX_NAMESPACE_DIR="$(ns_base_path "$AICTX_NAMESPACE")"
  export AICTX_SESS_DIR; AICTX_SESS_DIR="$(ns_resolve_dir "sessions" "$AICTX_NAMESPACE")"
  export AICTX_TRS_DIR; AICTX_TRS_DIR="$(ns_resolve_dir "transcripts" "$AICTX_NAMESPACE")"
  export AICTX_PENDING_DIR; AICTX_PENDING_DIR="$(ns_resolve_dir "pending" "$AICTX_NAMESPACE")"
  export AICTX_GITIGNORE; AICTX_GITIGNORE="$AICTX_ROOT/.gitignore"
  export AICTX_SCHEMA_FILE; AICTX_SCHEMA_FILE="$AICTX_DIR/.schema_version"
  export AICTX_INIT_MARK; AICTX_INIT_MARK="$AICTX_DIR/.initialized"
  export AICTX_DIGEST_FILE; AICTX_DIGEST_FILE="$AICTX_DIR/DIGEST.md"
  export AICTX_CONFIG_FILE; AICTX_CONFIG_FILE="$AICTX_DIR/config.json"
  export AICTX_CONSTITUTION_FILE; AICTX_CONSTITUTION_FILE="$AICTX_DIR/constitution.md"
  export AICTX_SPECS_DIR; AICTX_SPECS_DIR="$AICTX_DIR/specs"
  export AICTX_SPECIFY_DIR; AICTX_SPECIFY_DIR="$AICTX_ROOT/.specify"
  export AICTX_SPECIFY_MEMORY_DIR; AICTX_SPECIFY_MEMORY_DIR="$AICTX_SPECIFY_DIR/memory"
  export AICTX_ROOT_SPECS_DIR; AICTX_ROOT_SPECS_DIR="$AICTX_ROOT/specs"
  export AICTX_SPEC_KIT_META_FILE; AICTX_SPEC_KIT_META_FILE="$AICTX_DIR/spec-kit.json"
  export AICTX_SPEC_KIT_TEMPLATES_DIR; AICTX_SPEC_KIT_TEMPLATES_DIR="$AICTX_DIR/spec-kit-templates"
}

aictx_ensure_line_once(){
  local line="$1" file="$2"
  [[ -f "$file" ]] || touch "$file"
  grep -qxF "$line" "$file" || printf "\n%s\n" "$line" >> "$file"
}

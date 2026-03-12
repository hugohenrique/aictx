#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./template.sh
source "${AICTX_HOME}/lib/template.sh"

aictx_spec_kit_usage(){
  cat <<EOF
Usage: aictx spec-kit <command> [options]

Commands:
  install    [--source bundled|upstream] [--ref <tag-or-sha>] [--force]
  sync       [--ref <tag-or-sha>] [--force]
  status
  uninstall
EOF
}

_aictx_spec_kit_metadata_value(){
  local field="$1"
  [[ -f "$AICTX_SPEC_KIT_META_FILE" ]] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$AICTX_SPEC_KIT_META_FILE" "$field" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
value = data.get(sys.argv[2], "")
print(value if value is not None else "")
PY
  else
    sed -nE "s/.*\"$field\": \"([^\"]*)\".*/\\1/p" "$AICTX_SPEC_KIT_META_FILE" | head -n 1
  fi
}

aictx_spec_kit_mode(){ _aictx_spec_kit_metadata_value "mode" 2>/dev/null || true; }
aictx_spec_kit_source(){ _aictx_spec_kit_metadata_value "source" 2>/dev/null || true; }
aictx_spec_kit_ref(){ _aictx_spec_kit_metadata_value "ref" 2>/dev/null || true; }
aictx_spec_kit_installed(){ [[ -f "$AICTX_SPEC_KIT_META_FILE" ]]; }
aictx_spec_kit_templates_ready(){ [[ -d "$AICTX_SPEC_KIT_TEMPLATES_DIR" ]]; }
aictx_spec_kit_layout_active(){ [[ -f "$AICTX_SPECIFY_MEMORY_DIR/constitution.md" || -d "$AICTX_ROOT_SPECS_DIR" ]]; }

aictx_spec_kit_template_path(){
  local name="$1"
  if aictx_spec_kit_templates_ready && [[ -f "$AICTX_SPEC_KIT_TEMPLATES_DIR/$name" ]]; then
    echo "$AICTX_SPEC_KIT_TEMPLATES_DIR/$name"
  else
    case "$name" in
      constitution.md) aictx_template_path "context" "constitution.md" ;;
      spec.md|plan.md|tasks.md|meta.json) aictx_template_path "spec" "$name" ;;
      *) ai_die "unknown spec-kit template: $name" ;;
    esac
  fi
}

aictx_spec_kit_constitution_target(){
  if aictx_spec_kit_layout_active || aictx_spec_kit_installed; then
    echo "$AICTX_SPECIFY_MEMORY_DIR/constitution.md"
  else
    echo "$AICTX_CONSTITUTION_FILE"
  fi
}

aictx_spec_kit_specs_target(){
  if aictx_spec_kit_layout_active || aictx_spec_kit_installed; then
    echo "$AICTX_ROOT_SPECS_DIR"
  else
    echo "$AICTX_SPECS_DIR"
  fi
}

aictx_spec_kit_write_metadata(){
  local mode="$1" source="$2" ref="$3"
  cat > "$AICTX_SPEC_KIT_META_FILE" <<EOF
{
  "mode": "$mode",
  "source": "$source",
  "ref": "$ref",
  "installed_at": "$(date -Iseconds 2>/dev/null || date)"
}
EOF
}

aictx_spec_kit_copy_bundled_templates(){
  mkdir -p "$AICTX_SPEC_KIT_TEMPLATES_DIR"
  cp "$(aictx_template_path "context" "constitution.md")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/constitution.md"
  cp "$(aictx_template_path "spec" "spec.md")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/spec.md"
  cp "$(aictx_template_path "spec" "plan.md")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/plan.md"
  cp "$(aictx_template_path "spec" "tasks.md")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/tasks.md"
  cp "$(aictx_template_path "spec" "meta.json")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/meta.json"
}

aictx_spec_kit_fetch_upstream_templates(){
  local ref="$1"
  ai_cmd curl || ai_die "curl is required for --source upstream"
  mkdir -p "$AICTX_SPEC_KIT_TEMPLATES_DIR"

  local base="https://raw.githubusercontent.com/github/spec-kit/${ref}/templates"
  curl -fsSL "$base/constitution-template.md" -o "$AICTX_SPEC_KIT_TEMPLATES_DIR/constitution.md"
  curl -fsSL "$base/spec-template.md" -o "$AICTX_SPEC_KIT_TEMPLATES_DIR/spec.md"
  curl -fsSL "$base/plan-template.md" -o "$AICTX_SPEC_KIT_TEMPLATES_DIR/plan.md"
  curl -fsSL "$base/tasks-template.md" -o "$AICTX_SPEC_KIT_TEMPLATES_DIR/tasks.md"
  cp "$(aictx_template_path "spec" "meta.json")" "$AICTX_SPEC_KIT_TEMPLATES_DIR/meta.json"
}

aictx_spec_kit_install(){
  local source="bundled" ref="" force="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) source="${2:-}"; shift 2 ;;
      --ref) ref="${2:-}"; shift 2 ;;
      --force) force="1"; shift 1 ;;
      -h|--help) aictx_spec_kit_usage; return 0 ;;
      *) ai_die "unknown arg for spec-kit install: $1" ;;
    esac
  done

  aictx_paths_init
  aictx_bootstrap
  [[ "$source" == "bundled" || "$source" == "upstream" ]] || ai_die "--source must be bundled or upstream"
  [[ "$source" == "bundled" ]] && [[ -z "$ref" ]] && ref="internal"
  [[ "$source" == "upstream" ]] && [[ -z "$ref" ]] && ref="main"

  if aictx_spec_kit_installed && [[ "$force" != "1" ]]; then
    ai_die "spec-kit already installed; use --force to reinstall"
  fi

  if [[ "$source" == "bundled" ]]; then
    aictx_spec_kit_copy_bundled_templates
  else
    aictx_spec_kit_fetch_upstream_templates "$ref"
  fi

  mkdir -p "$AICTX_SPECIFY_MEMORY_DIR" "$AICTX_ROOT_SPECS_DIR"
  if [[ ! -f "$AICTX_SPECIFY_MEMORY_DIR/constitution.md" || "$force" == "1" ]]; then
    cp "$(aictx_spec_kit_template_path "constitution.md")" "$AICTX_SPECIFY_MEMORY_DIR/constitution.md"
  fi
  aictx_spec_kit_write_metadata "$source" "$source" "$ref"
  ai_log "spec-kit installed: mode=$source ref=$ref"
}

aictx_spec_kit_sync(){
  local ref="" force="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ref) ref="${2:-}"; shift 2 ;;
      --force) force="1"; shift 1 ;;
      -h|--help) aictx_spec_kit_usage; return 0 ;;
      *) ai_die "unknown arg for spec-kit sync: $1" ;;
    esac
  done

  aictx_paths_init
  aictx_bootstrap
  aictx_spec_kit_installed || ai_die "spec-kit is not installed"

  local mode source current_ref
  mode="$(aictx_spec_kit_mode)"
  source="$(aictx_spec_kit_source)"
  current_ref="$(aictx_spec_kit_ref)"
  [[ -n "$ref" ]] || ref="$current_ref"

  if [[ "$source" == "bundled" ]]; then
    aictx_spec_kit_copy_bundled_templates
    ref="internal"
  else
    aictx_spec_kit_fetch_upstream_templates "$ref"
  fi

  mkdir -p "$AICTX_SPECIFY_MEMORY_DIR" "$AICTX_ROOT_SPECS_DIR"
  if [[ ! -f "$AICTX_SPECIFY_MEMORY_DIR/constitution.md" || "$force" == "1" ]]; then
    cp "$(aictx_spec_kit_template_path "constitution.md")" "$AICTX_SPECIFY_MEMORY_DIR/constitution.md"
  fi
  aictx_spec_kit_write_metadata "$mode" "$source" "$ref"
  ai_log "spec-kit synced: mode=$mode ref=$ref"
}

aictx_spec_kit_status(){
  aictx_paths_init
  [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"

  echo "Spec Kit status"
  echo "installed: $(aictx_spec_kit_installed && echo yes || echo no)"
  echo "active_layout: $(aictx_spec_kit_layout_active && echo yes || echo no)"
  echo "mode: $(aictx_spec_kit_mode || echo "<none>")"
  echo "source: $(aictx_spec_kit_source || echo "<none>")"
  echo "ref: $(aictx_spec_kit_ref || echo "<none>")"
  echo "metadata: $AICTX_SPEC_KIT_META_FILE"
  echo "constitution: $(aictx_spec_kit_constitution_target)"
  echo "specs_dir: $(aictx_spec_kit_specs_target)"
  echo "templates_dir: $AICTX_SPEC_KIT_TEMPLATES_DIR"
}

aictx_spec_kit_uninstall(){
  aictx_paths_init
  [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
  rm -f "$AICTX_SPEC_KIT_META_FILE"
  rm -rf "$AICTX_SPEC_KIT_TEMPLATES_DIR"
  ai_log "spec-kit uninstalled; existing .specify/ and specs/ artifacts were left untouched"
}

aictx_spec_kit(){
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    -h|--help|"") aictx_spec_kit_usage ;;
    install) aictx_spec_kit_install "$@" ;;
    sync) aictx_spec_kit_sync "$@" ;;
    status) aictx_spec_kit_status ;;
    uninstall) aictx_spec_kit_uninstall ;;
    *) ai_die "unknown spec-kit command: $cmd" ;;
  esac
}

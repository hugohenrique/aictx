#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./migrate.sh
source "${AICTX_HOME}/lib/migrate.sh"

AICTX_SCHEMA_CURRENT="4"

aictx_copy_if_missing(){
  local src="$1" dst="$2"
  [[ -f "$dst" ]] || cp "$src" "$dst"
}

aictx_init_templates(){
  mkdir -p "$AICTX_SESS_DIR" "$AICTX_TRS_DIR" "$AICTX_PENDING_DIR"

  aictx_copy_if_missing "$AICTX_HOME/templates/PROMPT.md" "$AICTX_DIR/PROMPT.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/CONTEXT.md" "$AICTX_DIR/CONTEXT.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/DECISIONS.md" "$AICTX_DIR/DECISIONS.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/TODO.md" "$AICTX_DIR/TODO.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/config.json" "$AICTX_CONFIG_FILE"
  aictx_copy_if_missing "$AICTX_HOME/templates/DIGEST.md" "$AICTX_DIGEST_FILE"

  [[ -f "$AICTX_SCHEMA_FILE" ]] || echo "1" > "$AICTX_SCHEMA_FILE"
  [[ -f "$AICTX_INIT_MARK" ]] || date > "$AICTX_INIT_MARK"
}

aictx_gitignore_setup(){
  aictx_ensure_line_once ".aictx/" "$AICTX_GITIGNORE"
  aictx_ensure_line_once ".aictx/transcripts/" "$AICTX_GITIGNORE"
  aictx_ensure_line_once ".aictx/pending/" "$AICTX_GITIGNORE"
}

aictx_migrate_legacy_if_present(){
  [[ -d "$AICTX_DIR" ]] || mkdir -p "$AICTX_DIR"

  if [[ -d "$AICTX_LEGACY_DIR" && ! -d "$AICTX_SESS_DIR" ]]; then
    local bak="$AICTX_ROOT/.codex-context.bak-$(date +"%Y%m%d_%H%M%S")"
    ai_log "legacy found: $AICTX_LEGACY_DIR"
    ai_log "migrating to:  $AICTX_DIR"

    mkdir -p "$AICTX_DIR"
    for f in PROMPT.md CONTEXT.md DECISIONS.md TODO.md; do
      [[ -f "$AICTX_DIR/$f" ]] || [[ ! -f "$AICTX_LEGACY_DIR/$f" ]] || cp "$AICTX_LEGACY_DIR/$f" "$AICTX_DIR/$f"
    done
    [[ -d "$AICTX_LEGACY_DIR/sessions" ]] && { mkdir -p "$AICTX_SESS_DIR"; cp -n "$AICTX_LEGACY_DIR/sessions/"*.md "$AICTX_SESS_DIR/" 2>/dev/null || true; }
    [[ -d "$AICTX_LEGACY_DIR/transcripts" ]] && { mkdir -p "$AICTX_TRS_DIR"; cp -n "$AICTX_LEGACY_DIR/transcripts/"*.log "$AICTX_TRS_DIR/" 2>/dev/null || true; }

    mv "$AICTX_LEGACY_DIR" "$bak"
    ai_log "legacy moved to backup: $bak"
  fi
}

aictx_bootstrap(){
  aictx_paths_init
  aictx_migrate_legacy_if_present
  aictx_init_templates
  aictx_gitignore_setup
  aictx_run_migrations "$AICTX_SCHEMA_CURRENT"
}

aictx_init(){
  aictx_bootstrap
  ai_log "initialized: $AICTX_DIR"
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_schema_get(){
  [[ -f "$AICTX_SCHEMA_FILE" ]] && cat "$AICTX_SCHEMA_FILE" || echo "1"
}
aictx_schema_set(){ echo "$1" > "$AICTX_SCHEMA_FILE"; }

migrate_1_to_2(){
  mkdir -p "$AICTX_PENDING_DIR" "$AICTX_TRS_DIR"
  [[ -f "$AICTX_DIR/config.json" ]] || cp "$AICTX_HOME/templates/config.json" "$AICTX_DIR/config.json"
}

migrate_2_to_3(){
  [[ -f "$AICTX_DIGEST_FILE" ]] || cp "$AICTX_HOME/templates/DIGEST.md" "$AICTX_DIGEST_FILE"

  if [[ -f "$AICTX_DIR/config.json" ]] && ! grep -q '"prompt_mode"' "$AICTX_DIR/config.json"; then
    tmp="$(ai_mktemp)"
    if ! awk '
      BEGIN{added=0}
      /^\s*}\s*$/{ if(!added){ print "  ,"prompt_mode": "paths""; added=1 } }
      {print}
    ' "$AICTX_DIR/config.json" > "$tmp"; then
      ai_log "warning: migration 2->3 awk failed (prompt_mode)"
      rm -f "$tmp"
      return 0
    fi
    if grep -q '"prompt_mode"' "$tmp"; then
      mv "$tmp" "$AICTX_DIR/config.json"
    else
      rm -f "$tmp"
    fi
  fi
}

migrate_3_to_4(){
  if [[ -f "$AICTX_DIR/config.json" ]] && ! grep -q '"gemini_model"' "$AICTX_DIR/config.json"; then
    tmp="$(ai_mktemp)"
    if ! awk '
      BEGIN{added=0}
      /^\s*}\s*$/{ if(!added){ print "  ,"gemini_model": "auto""; added=1 } }
      {print}
    ' "$AICTX_DIR/config.json" > "$tmp"; then
      ai_log "warning: migration 3->4 awk failed"
      rm -f "$tmp"
      return 0
    fi
    if grep -q '"gemini_model"' "$tmp"; then
      mv "$tmp" "$AICTX_DIR/config.json"
    else
      rm -f "$tmp"
    fi
  fi
}

migrate_4_to_5(){
  if [[ -f "$AICTX_DIR/config.json" ]] && ! grep -q '"auto_cleanup"' "$AICTX_DIR/config.json"; then
    tmp="$(ai_mktemp)"
    if ! awk '
      BEGIN{added=0}
      /^\s*}\s*$/{ if(!added){ print "  ,\"auto_cleanup\": true"; print "  ,\"decision_keep_days\": 30"; print "  ,\"transcript_keep_days\": 30"; print "  ,\"token_budget_est\": 2500"; print "  ,\"warn_budget_pct\": 80"; print "  ,\"digest_max_lines\": 60"; print "  ,\"context_max_lines\": 20"; print "  ,\"decisions_max_chars\": 5000"; print "  ,\"todo_max_chars\": 1200"; added=1 } }
      {print}
    ' "$AICTX_DIR/config.json" > "$tmp"; then
      ai_log "warning: migration 4->5 awk failed"
      rm -f "$tmp"
      return 0
    fi
    if grep -q '"auto_cleanup"' "$tmp"; then
      mv "$tmp" "$AICTX_DIR/config.json"
    else
      rm -f "$tmp"
    fi
  fi

  # Backward-compatible alias: introduce auto_compact keys if absent.
  if [[ -f "$AICTX_DIR/config.json" ]] && ! grep -q '"auto_compact"' "$AICTX_DIR/config.json"; then
    tmp="$(ai_mktemp)"
    if ! awk '
      BEGIN{added=0}
      /^\s*}\s*$/{ if(!added){ print "  ,\"auto_compact\": true"; print "  ,\"auto_compact_ai\": false"; added=1 } }
      {print}
    ' "$AICTX_DIR/config.json" > "$tmp"; then
      ai_log "warning: migration 4->5 awk failed (auto_compact)"
      rm -f "$tmp"
      return 0
    fi
    if grep -q '"auto_compact"' "$tmp"; then
      mv "$tmp" "$AICTX_DIR/config.json"
    else
      rm -f "$tmp"
    fi
  fi
}

aictx_run_migrations(){
  local target="$1"
  local cur; cur="$(aictx_schema_get)"
  while [[ "$cur" -lt "$target" ]]; do
    local nxt=$((cur+1))
    ai_log "migrating schema $cur -> $nxt"
    "migrate_${cur}_to_${nxt}"
    aictx_schema_set "$nxt"
    cur="$nxt"
  done
}

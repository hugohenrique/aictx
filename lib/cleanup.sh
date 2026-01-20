#!/usr/bin/env bash
# Token optimization: session cleanup & consolidation

aictx_cleanup_old_sessions() {
  local sessions_dir="${AICTX_DIR}/sessions"
  local archive_dir="${AICTX_DIR}/archive"
  local current_time=$(date +%s)
  local seven_days=$((7 * 86400))
  local thirty_days=$((30 * 86400))

  [[ ! -d "$sessions_dir" ]] && return 0

  # Create archive dir if needed
  mkdir -p "$archive_dir"

  # Count sessions (keep last 5 always)
  local session_count=$(ls -1 "$sessions_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
  local keep_recent=5

  ai_log "Cleanup: found $session_count sessions"

  # Archive sessions >30 days old
  find "$sessions_dir" -name "*.md" -type f -mtime +30 | while read -r session; do
    local basename=$(basename "$session")
    ai_log "Archiving old session: $basename"
    mv "$session" "$archive_dir/" 2>/dev/null || true
  done

  # If still >5 sessions, keep only most recent 5
  if [[ $session_count -gt $keep_recent ]]; then
    ls -1t "$sessions_dir"/*.md 2>/dev/null | tail -n +$((keep_recent + 1)) | while read -r session; do
      local basename=$(basename "$session")
      ai_log "Archiving excess session: $basename"
      mv "$session" "$archive_dir/" 2>/dev/null || true
    done
  fi

  ai_log "Cleanup: sessions consolidated"
}

aictx_cleanup_pending() {
  local pending_dir="${AICTX_DIR}/pending"
  [[ ! -d "$pending_dir" ]] && return 0

  # Remove .done.json files >7 days old
  find "$pending_dir" -name "*.done.json" -type f -mtime +7 -delete 2>/dev/null || true

  # Remove orphaned .json files >3 days old (likely failed sessions)
  find "$pending_dir" -name "*.json" ! -name "*.done.json" -type f -mtime +3 -delete 2>/dev/null || true

  ai_log "Cleanup: pending artifacts removed"
}

aictx_cleanup_all() {
  ai_log "Starting cleanup..."
  aictx_cleanup_old_sessions
  aictx_cleanup_pending
  ai_log "Cleanup complete"
}

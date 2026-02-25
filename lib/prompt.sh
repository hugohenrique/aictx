#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

# Token optimization: lazy file loading helpers
aictx_should_load_todo(){
  local todo_file="$AICTX_DIR/TODO.md"
  [[ ! -f "$todo_file" ]] && return 1

  # Count non-empty, non-comment lines
  local line_count=$(grep -Ev '^#|^$|^\s*$' "$todo_file" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$line_count" -ge 3 ]] && return 0
  return 1
}

aictx_should_load_decisions(){
  local decisions_file="$AICTX_DIR/DECISIONS.md"
  [[ ! -f "$decisions_file" ]] && return 1

  # Check if has decisions from last 7 days (accurate date parsing if possible)
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$decisions_file" <<'PY' >/dev/null 2>&1
import re
import sys
from datetime import date, timedelta
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(errors="ignore")
dates = re.findall(r"^##\s+(\d{4}-\d{2}-\d{2})\s*$", text, flags=re.M)
if not dates:
    sys.exit(2)  # no parseable dates; fallback to line count

cutoff = date.today() - timedelta(days=7)
for d in dates:
    try:
        dt = date.fromisoformat(d)
    except ValueError:
        continue
    if dt >= cutoff:
        sys.exit(0)
sys.exit(1)
PY
    case "$?" in
      0) return 0 ;;
      1) return 1 ;;
      2) : ;; # fallback below
    esac
  fi

  # If can't parse dates, include if file has content
  local line_count=$(grep -Ev '^#|^$|^\s*$' "$decisions_file" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$line_count" -ge 3 ]] && return 0
  return 1
}

aictx_should_load_prev_session(){
  local prev_session="$1"
  [[ -z "$prev_session" ]] && return 1
  [[ ! -f "$prev_session" ]] && return 1

  # Skip if session is > 3 days old
  local three_days_ago_epoch=$(($(date +%s) - 259200))
  local session_mtime=$(stat -f %m "$prev_session" 2>/dev/null || stat -c %Y "$prev_session" 2>/dev/null || echo "0")

  [[ "$session_mtime" -ge "$three_days_ago_epoch" ]] && return 0
  return 1
}

aictx_should_load_context(){
  local context_file="$AICTX_DIR/CONTEXT.md"
  local cache_file="$AICTX_DIR/.context_hash"

  [[ ! -f "$context_file" ]] && return 1

  # Always load if no cache
  [[ ! -f "$cache_file" ]] && return 0

  # Check if cache is < 24h old
  local one_day_ago_epoch=$(($(date +%s) - 86400))
  local cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo "0")

  # If cache is old, reload
  [[ "$cache_mtime" -lt "$one_day_ago_epoch" ]] && return 0

  # Check if CONTEXT.md changed since cache
  local current_hash=$(md5 -q "$context_file" 2>/dev/null || md5sum "$context_file" 2>/dev/null | awk '{print $1}')
  local cached_hash=$(cat "$cache_file" 2>/dev/null || echo "")

  # If hash differs, reload
  [[ "$current_hash" != "$cached_hash" ]] && return 0

  # Context unchanged and cache fresh - skip
  return 1
}

aictx_update_context_cache(){
  local context_file="$AICTX_DIR/CONTEXT.md"
  local cache_file="$AICTX_DIR/.context_hash"

  [[ ! -f "$context_file" ]] && return 0

  local current_hash=$(md5 -q "$context_file" 2>/dev/null || md5sum "$context_file" 2>/dev/null | awk '{print $1}')
  echo "$current_hash" > "$cache_file"
}

# Phase 3: Delta-based DIGEST optimization
aictx_snapshot_digest(){
  # Save DIGEST snapshot before run for delta comparison
  local digest_file="$AICTX_DIGEST_FILE"
  local snapshot_file="$AICTX_DIR/.digest_snapshot"

  [[ -f "$digest_file" ]] && cp "$digest_file" "$snapshot_file" 2>/dev/null || true
}

aictx_has_digest_snapshot(){
  [[ -f "$AICTX_DIR/.digest_snapshot" ]] && return 0
  return 1
}

aictx_build_finalize_prompt(){
  local session_file="$1"
  local transcript_file="$2"
  local out; out="$(ai_mktemp)"

  # Phase 3: Delta-based DIGEST optimization
  # Only use delta if it actually saves tokens vs standard reference
  local use_delta=0
  local digest_diff_content=""

  if aictx_has_digest_snapshot; then
    local snapshot="$AICTX_DIR/.digest_snapshot"
    local current="$AICTX_DIGEST_FILE"

    # Check if DIGEST changed
    if ! diff -q "$snapshot" "$current" >/dev/null 2>&1; then
      # Create diff (unified format, minimal context)
      local digest_diff
      digest_diff=$(diff -U 1 "$snapshot" "$current" 2>/dev/null | tail -n +3 || echo "")

      if [[ -n "$digest_diff" ]]; then
        # Count diff size vs alternative (just include current DIGEST in inline mode costs ~200 tokens)
        # In paths mode, referencing DIGEST.md is ~3 words, diff might be 20-100 words
        # Only use delta if diff is < 15 words (small change worth embedding)
        local diff_words=$(echo "$digest_diff" | wc -w | tr -d ' ')

        if [[ "$diff_words" -lt 15 ]]; then
          # Very small delta - worth including inline
          use_delta=1
          digest_diff_content="$digest_diff"
        fi
      fi
    fi
  fi

  # Build finalize prompt
  if [[ "$use_delta" == "1" && -n "$digest_diff_content" ]]; then
    # Delta mode: include minimal diff for small changes
    {
      echo "Output ONE git-apply diff."
      echo ""
      echo "DIGEST.md delta:"
      echo "\`\`\`diff"
      echo "$digest_diff_content"
      echo "\`\`\`"
      echo ""
      echo "Update from $transcript_file:"
      echo "- DIGEST.md: apply delta above (≤60 lines, bullets)"
      echo "- CONTEXT.md (≤20 lines, stable)"
      echo "- DECISIONS.md (append+date)"
      echo "- TODO.md (actionable)"
      echo "- $session_file (objective/done/decisions/next)"
      echo ""
      echo "Rules: no invented facts; prefer DIGEST; minimal edits."
    } > "$out"
  else
    # Standard mode: use template (paths reference is more efficient for large changes)
    sed -e "s|{{SESSION_FILE}}|$session_file|g" \
        -e "s|{{TRANSCRIPT_FILE}}|$transcript_file|g" \
        "${AICTX_HOME}/templates/FINALIZE_PROMPT.md" > "$out"
  fi

  echo "$out"
}

aictx_build_prompt(){
  local session_file="$1"
  local prev_session="$2"
  local mode="${3:-paths}"
  local out; out="$(ai_mktemp)"

  if [[ "$mode" == "inline" ]]; then
    {
      echo "# aictx inline"
      cat "$AICTX_DIR/PROMPT.md"
      echo "## DIGEST.md"
      cat "$AICTX_DIGEST_FILE" 2>/dev/null || true
      echo "## CONTEXT.md"
      cat "$AICTX_DIR/CONTEXT.md"
      echo "## DECISIONS.md"
      cat "$AICTX_DIR/DECISIONS.md"
      echo "## TODO.md"
      cat "$AICTX_DIR/TODO.md"
      if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]]; then
        echo "## Previous session"
        cat "$prev_session"
      fi
      echo "## Session file to update"
      echo "$session_file"
    } > "$out"
  else
    # Token optimization: lazy file loading
    local optional_files=""
    local context_note=""

    # Conditional context loading (token optimization)
    if aictx_should_load_context; then
      optional_files="$AICTX_DIR/CONTEXT.md"
      aictx_update_context_cache
    else
      context_note=" (CONTEXT.md cached, read if needed)"
    fi

    # Only include DECISIONS.md if has recent content
    if aictx_should_load_decisions; then
      optional_files="$optional_files $AICTX_DIR/DECISIONS.md"
    fi

    # Only include TODO.md if has actual tasks
    if aictx_should_load_todo; then
      optional_files="$optional_files $AICTX_DIR/TODO.md"
    fi

    # Only include prev session if recent (< 3 days)
    if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]] && aictx_should_load_prev_session "$prev_session"; then
      optional_files="$optional_files $prev_session"
    fi

    {
      echo "# aictx paths"
      local prompt_rel="${AICTX_DIR#$AICTX_ROOT/}/PROMPT.md"
      local digest_rel="${AICTX_DIGEST_FILE#$AICTX_ROOT/}"
      local opt_rel=""
      for f in $optional_files; do
        [[ -n "$opt_rel" ]] && opt_rel+=" "
        opt_rel+="${f#$AICTX_ROOT/}"
      done

      local session_rel="${session_file#$AICTX_ROOT/}"

      if [[ -n "$opt_rel" ]]; then
        echo "Read: $prompt_rel; $digest_rel first. Opt: $opt_rel$context_note"
      else
        echo "Read: $prompt_rel; $digest_rel first.$context_note"
      fi
      echo "Session: $session_rel"
    } > "$out"
  fi

  echo "$out"
}

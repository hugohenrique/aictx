#!/usr/bin/env bash
# Token optimization: session cleanup & consolidation
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"

aictx_cleanup_old_sessions() {
  local keep_recent=5
  local sessions_dir

  for sessions_dir in $(ns_aictx_dirs "sessions"); do
    [[ ! -d "$sessions_dir" ]] && continue

    local base_dir archive_dir session_count
    base_dir="$(dirname "$sessions_dir")"
    archive_dir="$base_dir/archive"
    mkdir -p "$archive_dir"

    session_count="$(ls -1 "$sessions_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    ai_log "Cleanup: found $session_count sessions in $sessions_dir"

    find "$sessions_dir" -name "*.md" -type f -mtime +30 | while read -r session; do
      local basename
      basename="$(basename "$session")"
      ai_log "Archiving old session: $basename"
      mv "$session" "$archive_dir/" 2>/dev/null || true
    done

    if [[ $session_count -gt $keep_recent ]]; then
      ls -1t "$sessions_dir"/*.md 2>/dev/null | tail -n +$((keep_recent + 1)) | while read -r session; do
        local basename
        basename="$(basename "$session")"
        ai_log "Archiving excess session: $basename"
        mv "$session" "$archive_dir/" 2>/dev/null || true
      done
    fi
  done

  ai_log "Cleanup: sessions consolidated (default + namespaces)"
}

aictx_cleanup_pending() {
  local pending_dir
  for pending_dir in $(ns_aictx_dirs "pending"); do
    [[ ! -d "$pending_dir" ]] && continue
    find "$pending_dir" -name "*.done.json" -type f -mtime +7 -delete 2>/dev/null || true
    find "$pending_dir" -name "*.json" ! -name "*.done.json" -type f -mtime +3 -delete 2>/dev/null || true
  done

  ai_log "Cleanup: pending artifacts removed (default + namespaces)"
}

aictx_cleanup_transcripts() {
  local keep_days="${AICTX_TRANSCRIPT_KEEP_DAYS:-30}"
  local transcripts_dir

  for transcripts_dir in $(ns_aictx_dirs "transcripts"); do
    [[ ! -d "$transcripts_dir" ]] && continue
    local base_dir archive_dir
    base_dir="$(dirname "$transcripts_dir")"
    archive_dir="$base_dir/archive/transcripts"
    mkdir -p "$archive_dir"

    find "$transcripts_dir" -name "*.log" -type f -mtime +"$keep_days" | while read -r log; do
      local basename
      basename="$(basename "$log")"
      ai_log "Archiving old transcript: $basename"
      mv "$log" "$archive_dir/" 2>/dev/null || true
    done
  done
}

aictx_cleanup_decisions() {
  local decisions_file="${AICTX_DIR}/DECISIONS.md"
  [[ -f "$decisions_file" ]] || return 0

  command -v python3 >/dev/null 2>&1 || { ai_log "Python3 not found, skipping decisions cleanup"; return 0; }

  local keep_days="${AICTX_DECISION_KEEP_DAYS:-30}"
  local max_chars="${AICTX_DECISIONS_MAX_CHARS:-5000}"
  local archive_dir="${AICTX_DIR}/archive"
  local before_chars after_chars
  mkdir -p "$archive_dir"
  before_chars="$(wc -c < "$decisions_file" 2>/dev/null | tr -d ' ' || echo 0)"

  python3 - "$decisions_file" "$archive_dir" "$keep_days" "$max_chars" <<'PY'
import re
import sys
from datetime import date, timedelta
from pathlib import Path

decisions_path = Path(sys.argv[1])
archive_dir = Path(sys.argv[2])
keep_days = int(sys.argv[3])
max_chars = int(sys.argv[4])

text = decisions_path.read_text(errors="ignore")
lines = text.splitlines()

date_re = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\s*$")

preamble = []
blocks = []
current = None

for line in lines:
    match = date_re.match(line)
    if match:
        if current:
            blocks.append(current)
        current = {"date": match.group(1), "lines": [line]}
    else:
        if current is None:
            preamble.append(line)
        else:
            current["lines"].append(line)

if current:
    blocks.append(current)

if not blocks:
    sys.exit(0)

cutoff = date.today() - timedelta(days=keep_days)
keep_blocks = []
archive_blocks = {}

for block in blocks:
    try:
        block_date = date.fromisoformat(block["date"])
    except ValueError:
        keep_blocks.append(block)
        continue
    if block_date < cutoff:
        month = block["date"][:7]
        archive_blocks.setdefault(month, []).append(block)
    else:
        keep_blocks.append(block)

def write_archive(month, blocks_to_archive):
    archive_path = archive_dir / f"DECISIONS_{month}.md"
    if archive_path.exists():
        existing = archive_path.read_text(errors="ignore").rstrip()
    else:
        existing = f"# Decisions Archive {month}"
    content_lines = [existing, ""]
    for b in blocks_to_archive:
        content_lines.extend(b["lines"])
        content_lines.append("")
    archive_path.write_text("\n".join(content_lines).rstrip() + "\n")

for month, month_blocks in archive_blocks.items():
    write_archive(month, month_blocks)

def render(preamble_lines, decision_blocks):
    out = []
    out.extend(preamble_lines)
    if decision_blocks:
        if out and out[-1].strip():
            out.append("")
        for b in decision_blocks:
            out.extend(b["lines"])
            out.append("")
    return "\n".join(out).rstrip() + "\n"

# Size cap: if decisions are still too large, keep removing oldest blocks.
rendered = render(preamble, keep_blocks)
if len(rendered) > max_chars and keep_blocks:
    kept = list(keep_blocks)
    while len(rendered) > max_chars and len(kept) > 1:
        oldest = kept.pop(0)
        month = oldest["date"][:7]
        archive_blocks.setdefault(month, []).append(oldest)
        rendered = render(preamble, kept)
    keep_blocks = kept

new_lines = []
new_lines.extend(preamble)
if keep_blocks:
    if new_lines and new_lines[-1].strip():
        new_lines.append("")
    for b in keep_blocks:
        new_lines.extend(b["lines"])
        new_lines.append("")

decisions_path.write_text("\n".join(new_lines).rstrip() + "\n")
PY

  after_chars="$(wc -c < "$decisions_file" 2>/dev/null | tr -d ' ' || echo 0)"
  if [[ "$after_chars" -lt "$before_chars" ]]; then
    ai_log "Cleanup: DECISIONS.md compacted ($before_chars -> $after_chars chars; target <= $max_chars)"
  fi
}

aictx_cleanup_all() {
  aictx_paths_init
  aictx_load_config
  ai_log "Starting cleanup..."
  aictx_cleanup_old_sessions
  aictx_cleanup_pending
  aictx_cleanup_transcripts
  aictx_cleanup_decisions
  ai_log "Cleanup complete"
}

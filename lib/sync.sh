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

AICTX_AGENTS_START="<!-- AICTX START -->"
AICTX_AGENTS_END="<!-- AICTX END -->"

_aictx_agents_block(){
  cat <<'BLOCK'
<!-- AICTX START -->
## aictx
- Follow the aictx paths header: always read PROMPT.md and DIGEST.md first.
- Read optional files only if they are listed in the header.
- Do not read older sessions unless explicitly listed.
- Keep DIGEST <= 60 lines, bullets only.
- Keep CONTEXT <= 20 lines and stable.
- Append DECISIONS with date headers.
- Keep TODO actionable only.
<!-- AICTX END -->
BLOCK
}

aictx_sync_agents_md(){
  local file="$AICTX_ROOT/AGENTS.md"
  local block_file
  block_file="$(ai_mktemp)"
  _aictx_agents_block > "$block_file"

  if [[ ! -f "$file" ]]; then
    cat "$block_file" > "$file"
    rm -f "$block_file"
    return
  fi

  if grep -q "$AICTX_AGENTS_START" "$file" && grep -q "$AICTX_AGENTS_END" "$file"; then
    local tmp
    tmp="$(ai_mktemp)"
    awk -v start="$AICTX_AGENTS_START" -v end="$AICTX_AGENTS_END" -v block_file="$block_file" '
      function emit_block(   line) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
      BEGIN {in_block=0; replaced=0}
      $0==start {
        if (replaced==0) {
          emit_block()
          replaced=1
        }
        in_block=1
        next
      }
      $0==end { in_block=0; next }
      in_block==0 { print }
      END {
        if (replaced==0) {
          if (NR>0) print ""
          emit_block()
        }
      }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  elif grep -q '<!-- aictx -->' "$file"; then
    local tmp
    tmp="$(ai_mktemp)"
    awk -v block_file="$block_file" '
      function emit_block(   line) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
      BEGIN {skip=0; inserted=0}
      /^<!-- aictx -->$/ {
        if (inserted==0) {
          emit_block()
          inserted=1
        }
        skip=1
        next
      }
      skip==1 {
        if ($0 ~ /^## /) {
          skip=0
          print $0
        }
        next
      }
      { print }
      END {
        if (inserted==0) {
          if (NR>0) print ""
          emit_block()
        }
      }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf '\n' >> "$file"
    cat "$block_file" >> "$file"
  fi

  rm -f "$block_file"
}

aictx_sync(){
  aictx_paths_init
  aictx_init_templates
  aictx_init_project_skill
  aictx_sync_agents_md
  ai_log "sync complete (.aictx, AGENTS.md, project skill)"
}

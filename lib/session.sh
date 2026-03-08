#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./template.sh
source "${AICTX_HOME}/lib/template.sh"

aictx_new_session(){
  local ts file
  ts="$(date +"%Y-%m-%d_%H-%M")"
  file="$AICTX_SESS_DIR/$ts.md"
  cp "$(aictx_template_path "context" "SESSION.md")" "$file"
  if sed -i.bak "s/{{TS}}/$ts/g" "$file" 2>/dev/null; then
    rm -f "$file.bak" 2>/dev/null || true
  else
    sed -i '' "s/{{TS}}/$ts/g" "$file" 2>/dev/null || ai_log "warning: sed substitution failed on $file"
  fi
  echo "$file"
}

aictx_session_pick(){
  local last now mtime age
  last="$(ai_latest_file "$AICTX_SESS_DIR" "*.md")"
  [[ -n "$last" ]] || { aictx_new_session; return; }

  now="$(date +%s)"
  mtime="$(ai_stat_mtime "$last")"
  age=$(( now - mtime ))

  if [[ "$age" -le "$AICTX_SESSION_REUSE_SECONDS" ]]; then
    echo "$last"
  else
    aictx_new_session
  fi
}

aictx_pending_create(){
  local engine="$1" model="$2" session_file="$3" transcript="$4"
  local skills_csv="${5:-}" intent="${6:-}"
  local id; id="$(date +"%Y%m%d_%H%M%S")_$$"
  local p="$AICTX_PENDING_DIR/$id.json"

  local sess_abs="$session_file" trs_abs="$transcript"
  if command -v realpath >/dev/null 2>&1; then
    sess_abs="$(realpath "$session_file" 2>/dev/null || echo "$session_file")"
    trs_abs="$(realpath "$transcript" 2>/dev/null || echo "$transcript")"
  elif command -v python3 >/dev/null 2>&1; then
    sess_abs="$(python3 - <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
"$session_file" 2>/dev/null || echo "$session_file")"
    trs_abs="$(python3 - <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
"$transcript" 2>/dev/null || echo "$transcript")"
  fi

  local skills_json="[]"
  if [[ -n "$skills_csv" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      skills_json="$(python3 - "$skills_csv" <<'PY'
import json
import sys
parts = [p.strip() for p in sys.argv[1].split(",") if p.strip()]
print(json.dumps(parts))
PY
)"
    else
      skills_json="[]"
    fi
  fi

  cat > "$p" <<EOF
{
  "engine": "$engine",
  "model": "$model",
  "session": "$sess_abs",
  "transcript": "$trs_abs",
  "intent": "$intent",
  "skills": $skills_json,
  "created_at": "$(date -Iseconds 2>/dev/null || date)"
}
EOF
  echo "$p"
}

aictx_pending_mark_done(){
  local pending="$1"
  [[ -f "$pending" ]] && mv "$pending" "${pending%.json}.done.json" 2>/dev/null || true
}

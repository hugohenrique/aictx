#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

_aictx_hash_file(){
  local file="$1"
  md5 -q "$file" 2>/dev/null || md5sum "$file" 2>/dev/null | awk '{print $1}'
}

aictx_should_load_todo(){
  local todo_file="$AICTX_DIR/TODO.md"
  [[ -f "$todo_file" ]] || return 1

  local line_count
  line_count="$(grep -Ev '^#|^$|^[[:space:]]*$' "$todo_file" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$line_count" -ge 3 ]]
}

aictx_should_load_decisions(){
  local decisions_file="$AICTX_DIR/DECISIONS.md"
  [[ -f "$decisions_file" ]] || return 1

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
    sys.exit(2)

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
      2) ;;
    esac
  fi

  local line_count
  line_count="$(grep -Ev '^#|^$|^[[:space:]]*$' "$decisions_file" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$line_count" -ge 3 ]]
}

aictx_should_load_prev_session(){
  local prev_session="$1"
  [[ -n "$prev_session" && -f "$prev_session" ]] || return 1

  local three_days_ago_epoch session_mtime
  three_days_ago_epoch="$(( $(date +%s) - 259200 ))"
  session_mtime="$(stat -f %m "$prev_session" 2>/dev/null || stat -c %Y "$prev_session" 2>/dev/null || echo 0)"

  [[ "$session_mtime" -ge "$three_days_ago_epoch" ]]
}

aictx_should_load_context(){
  local context_file="$AICTX_DIR/CONTEXT.md"
  local cache_file="$AICTX_DIR/.context_hash"

  [[ -f "$context_file" ]] || return 1
  [[ -f "$cache_file" ]] || return 0

  local one_day_ago_epoch cache_mtime
  one_day_ago_epoch="$(( $(date +%s) - 86400 ))"
  cache_mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
  [[ "$cache_mtime" -lt "$one_day_ago_epoch" ]] && return 0

  local current_hash cached_hash
  current_hash="$(_aictx_hash_file "$context_file")"
  cached_hash="$(cat "$cache_file" 2>/dev/null || echo "")"

  [[ "$current_hash" != "$cached_hash" ]]
}

aictx_update_context_cache(){
  local context_file="$AICTX_DIR/CONTEXT.md"
  local cache_file="$AICTX_DIR/.context_hash"

  [[ -f "$context_file" ]] || return 0
  _aictx_hash_file "$context_file" > "$cache_file"
}

aictx_context_tokens_est(){
  local chars="${1:-0}"
  echo $(((chars + 3) / 4))
}

aictx_context_plan(){
  local session_file="$1"
  local prev_session="$2"
  local mode="${3:-${AICTX_PROMPT_MODE:-paths}}"

  export AICTX_PLAN_LOAD_PROMPT=1
  export AICTX_PLAN_LOAD_DIGEST=1
  export AICTX_PLAN_LOAD_CONTEXT=0
  export AICTX_PLAN_LOAD_DECISIONS=0
  export AICTX_PLAN_LOAD_TODO=0
  export AICTX_PLAN_LOAD_PREV_SESSION=0
  export AICTX_PLAN_LOAD_CURRENT_SESSION=1
  export AICTX_PLAN_CONTEXT_NOTE=""

  export AICTX_PLAN_REASON_PROMPT="mandatory L1"
  export AICTX_PLAN_REASON_DIGEST="mandatory L2"
  export AICTX_PLAN_REASON_CONTEXT="skipped"
  export AICTX_PLAN_REASON_DECISIONS="skipped"
  export AICTX_PLAN_REASON_TODO="skipped"
  export AICTX_PLAN_REASON_PREV_SESSION="skipped"
  export AICTX_PLAN_REASON_CURRENT_SESSION="mandatory L7"

  if [[ "$mode" == "inline" ]]; then
    export AICTX_PLAN_LOAD_CONTEXT=1
    export AICTX_PLAN_LOAD_DECISIONS=1
    export AICTX_PLAN_LOAD_TODO=1
    export AICTX_PLAN_REASON_CONTEXT="inline mode includes L3"
    export AICTX_PLAN_REASON_DECISIONS="inline mode includes L4"
    export AICTX_PLAN_REASON_TODO="inline mode includes L5"

    if [[ -n "$prev_session" && "$prev_session" != "$session_file" && -f "$prev_session" ]]; then
      export AICTX_PLAN_LOAD_PREV_SESSION=1
      export AICTX_PLAN_REASON_PREV_SESSION="inline mode includes L6"
    fi
  else
    if aictx_should_load_context; then
      export AICTX_PLAN_LOAD_CONTEXT=1
      export AICTX_PLAN_REASON_CONTEXT="changed/stale cache for L3"
      aictx_update_context_cache
    else
      export AICTX_PLAN_CONTEXT_NOTE=" (CONTEXT.md cached, read if needed)"
      export AICTX_PLAN_REASON_CONTEXT="fresh context cache; L3 optional"
    fi

    if aictx_should_load_decisions; then
      export AICTX_PLAN_LOAD_DECISIONS=1
      export AICTX_PLAN_REASON_DECISIONS="recent/non-empty decisions for L4"
    fi

    if aictx_should_load_todo; then
      export AICTX_PLAN_LOAD_TODO=1
      export AICTX_PLAN_REASON_TODO="actionable TODO content for L5"
    fi

    if [[ -n "$prev_session" && "$prev_session" != "$session_file" ]] && aictx_should_load_prev_session "$prev_session"; then
      export AICTX_PLAN_LOAD_PREV_SESSION=1
      export AICTX_PLAN_REASON_PREV_SESSION="recent previous session for L6"
    fi
  fi

  local total_chars=0
  local file
  for file in "$AICTX_DIR/PROMPT.md" "$AICTX_DIGEST_FILE"; do
    [[ -f "$file" ]] && total_chars=$((total_chars + $(wc -c < "$file" | tr -d ' ')))
  done

  if [[ "$AICTX_PLAN_LOAD_CONTEXT" == "1" && -f "$AICTX_DIR/CONTEXT.md" ]]; then
    total_chars=$((total_chars + $(wc -c < "$AICTX_DIR/CONTEXT.md" | tr -d ' ')))
  fi
  if [[ "$AICTX_PLAN_LOAD_DECISIONS" == "1" && -f "$AICTX_DIR/DECISIONS.md" ]]; then
    total_chars=$((total_chars + $(wc -c < "$AICTX_DIR/DECISIONS.md" | tr -d ' ')))
  fi
  if [[ "$AICTX_PLAN_LOAD_TODO" == "1" && -f "$AICTX_DIR/TODO.md" ]]; then
    total_chars=$((total_chars + $(wc -c < "$AICTX_DIR/TODO.md" | tr -d ' ')))
  fi
  if [[ "$AICTX_PLAN_LOAD_PREV_SESSION" == "1" && -f "$prev_session" ]]; then
    total_chars=$((total_chars + $(wc -c < "$prev_session" | tr -d ' ')))
  fi

  export AICTX_PLAN_ESTIMATED_CHARS="$total_chars"
  export AICTX_PLAN_ESTIMATED_TOKENS="$(aictx_context_tokens_est "$total_chars")"
  export AICTX_PLAN_ESTIMATED_BUDGET_HINT="~${AICTX_PLAN_ESTIMATED_TOKENS} tokens (${AICTX_PLAN_ESTIMATED_CHARS} chars)"

  if [[ "${4:-}" == "print" ]]; then
    cat <<PLAN
load_prompt=$AICTX_PLAN_LOAD_PROMPT
load_digest=$AICTX_PLAN_LOAD_DIGEST
load_context=$AICTX_PLAN_LOAD_CONTEXT
load_decisions=$AICTX_PLAN_LOAD_DECISIONS
load_todo=$AICTX_PLAN_LOAD_TODO
load_prev_session=$AICTX_PLAN_LOAD_PREV_SESSION
context_note=$AICTX_PLAN_CONTEXT_NOTE
estimated_budget_hint=$AICTX_PLAN_ESTIMATED_BUDGET_HINT
PLAN
  fi
}

aictx_context_explain(){
  cat <<EXPLAIN
Context plan (mode=${AICTX_PROMPT_MODE:-paths})
- L1 PROMPT.md: ${AICTX_PLAN_LOAD_PROMPT} (${AICTX_PLAN_REASON_PROMPT})
- L2 DIGEST.md: ${AICTX_PLAN_LOAD_DIGEST} (${AICTX_PLAN_REASON_DIGEST})
- L3 CONTEXT.md: ${AICTX_PLAN_LOAD_CONTEXT} (${AICTX_PLAN_REASON_CONTEXT})
- L4 DECISIONS.md: ${AICTX_PLAN_LOAD_DECISIONS} (${AICTX_PLAN_REASON_DECISIONS})
- L5 TODO.md: ${AICTX_PLAN_LOAD_TODO} (${AICTX_PLAN_REASON_TODO})
- L6 previous session: ${AICTX_PLAN_LOAD_PREV_SESSION} (${AICTX_PLAN_REASON_PREV_SESSION})
- L7 current session: ${AICTX_PLAN_LOAD_CURRENT_SESSION} (${AICTX_PLAN_REASON_CURRENT_SESSION})
- estimated budget: ${AICTX_PLAN_ESTIMATED_BUDGET_HINT}
EXPLAIN
}

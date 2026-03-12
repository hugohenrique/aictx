#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./config.sh
source "${AICTX_HOME}/lib/config.sh"

_aictx_color(){
  local code="$1"
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    tput setaf "$code"
  fi
}

_aictx_reset(){
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    tput sgr0
  fi
}

_aictx_validate_print(){
  local status="$1" message="$2"
  case "$status" in
    ok)
      printf "%s[OK]%s %s\n" "$(_aictx_color 2)" "$(_aictx_reset)" "$message"
      ;;
    warn)
      printf "%s[WARN]%s %s\n" "$(_aictx_color 3)" "$(_aictx_reset)" "$message"
      ;;
    fail)
      printf "%s[FAIL]%s %s\n" "$(_aictx_color 1)" "$(_aictx_reset)" "$message"
      ;;
  esac
}

_aictx_validate_json(){
  local file="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY' >/dev/null 2>&1
import json
import pathlib
import sys
json.loads(pathlib.Path(sys.argv[1]).read_text())
PY
    return $?
  fi

  grep -q '{' "$file" && grep -q '}' "$file"
}

aictx_validate(){
  local strict="0"
  if [[ "${1:-}" == "--strict" ]]; then
    strict="1"
    shift
  fi
  [[ $# -eq 0 ]] || ai_die "unknown arg for validate: $1 (use: aictx validate [--strict])"

  aictx_paths_init
  local failures=0

  if [[ -d "$AICTX_DIR" ]]; then
    _aictx_validate_print ok ".aictx exists"
  else
    _aictx_validate_print fail ".aictx missing"
    failures=$((failures + 1))
  fi

  local required_context=(PROMPT.md DIGEST.md CONTEXT.md DECISIONS.md TODO.md)
  local file
  for file in "${required_context[@]}"; do
    if [[ -f "$AICTX_DIR/$file" ]]; then
      _aictx_validate_print ok "$file present"
    else
      _aictx_validate_print fail "$file missing"
      failures=$((failures + 1))
    fi
  done

  if [[ -f "$AICTX_CONFIG_FILE" ]] && _aictx_validate_json "$AICTX_CONFIG_FILE"; then
    _aictx_validate_print ok "config.json parseable"
  else
    _aictx_validate_print fail "config.json invalid or missing"
    failures=$((failures + 1))
  fi

  if [[ -d "$AICTX_DIR/skills" ]]; then
    local skill_count
    skill_count="$(find "$AICTX_DIR/skills" -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$skill_count" -gt 0 ]]; then
      _aictx_validate_print ok "local skills present ($skill_count)"
    else
      _aictx_validate_print fail "skills directory exists but no SKILL.md found"
      failures=$((failures + 1))
    fi
  else
    _aictx_validate_print warn "no local .aictx/skills directory"
  fi

  if [[ -f "$AICTX_ROOT/AGENTS.md" ]] && grep -qi "## aictx" "$AICTX_ROOT/AGENTS.md"; then
    _aictx_validate_print ok "AGENTS.md contains aictx section"
  else
    _aictx_validate_print fail "AGENTS.md missing aictx section"
    failures=$((failures + 1))
  fi

  if [[ -f "$AICTX_ROOT/GEMINI.md" ]]; then
    _aictx_validate_print ok "GEMINI.md present (engine-specific adapter)"
  else
    _aictx_validate_print warn "GEMINI.md absent (created on demand for Gemini CLI)"
  fi

  if [[ "$strict" == "1" ]]; then
    aictx_load_config

    local digest_nonempty context_nonempty decisions_chars todo_chars
    digest_nonempty="$(grep -cve '^[[:space:]]*$' "$AICTX_DIGEST_FILE" 2>/dev/null || echo 0)"
    context_nonempty="$(grep -cve '^[[:space:]]*$' "$AICTX_DIR/CONTEXT.md" 2>/dev/null || echo 0)"
    decisions_chars="$(wc -c < "$AICTX_DIR/DECISIONS.md" 2>/dev/null | tr -d ' ' || echo 0)"
    todo_chars="$(wc -c < "$AICTX_DIR/TODO.md" 2>/dev/null | tr -d ' ' || echo 0)"

    if [[ "$digest_nonempty" -le "${AICTX_DIGEST_MAX_LINES:-60}" ]]; then
      _aictx_validate_print ok "DIGEST non-empty lines within limit (${digest_nonempty}/${AICTX_DIGEST_MAX_LINES})"
    else
      _aictx_validate_print fail "DIGEST exceeds limit (${digest_nonempty}/${AICTX_DIGEST_MAX_LINES})"
      failures=$((failures + 1))
    fi

    if [[ "$context_nonempty" -le "${AICTX_CONTEXT_MAX_LINES:-20}" ]]; then
      _aictx_validate_print ok "CONTEXT non-empty lines within limit (${context_nonempty}/${AICTX_CONTEXT_MAX_LINES})"
    else
      _aictx_validate_print fail "CONTEXT exceeds limit (${context_nonempty}/${AICTX_CONTEXT_MAX_LINES})"
      failures=$((failures + 1))
    fi

    if [[ "$decisions_chars" -le "${AICTX_DECISIONS_MAX_CHARS:-5000}" ]]; then
      _aictx_validate_print ok "DECISIONS size within limit (${decisions_chars}/${AICTX_DECISIONS_MAX_CHARS})"
    else
      _aictx_validate_print fail "DECISIONS too large (${decisions_chars}/${AICTX_DECISIONS_MAX_CHARS})"
      failures=$((failures + 1))
    fi

    if [[ "$todo_chars" -le "${AICTX_TODO_MAX_CHARS:-1200}" ]]; then
      _aictx_validate_print ok "TODO size within limit (${todo_chars}/${AICTX_TODO_MAX_CHARS})"
    else
      _aictx_validate_print fail "TODO too large (${todo_chars}/${AICTX_TODO_MAX_CHARS})"
      failures=$((failures + 1))
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    ai_log "validate failed with $failures issue(s)"
    return 1
  fi

  ai_log "validate passed"
}

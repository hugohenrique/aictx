#!/usr/bin/env bash
set -euo pipefail

ai_die(){ echo "aictx: $*" >&2; exit 1; }
ai_log(){ echo "aictx: $*" >&2; }

ai_is_macos(){ [[ "$(uname -s)" == "Darwin" ]]; }
ai_cmd(){ command -v "$1" >/dev/null 2>&1; }

ai_project_root(){
  if ai_cmd git && git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

ai_mktemp(){
  if ai_is_macos; then mktemp -t aictx.XXXXXX
  else mktemp
  fi
}

ai_sanitize_transcript(){
  # Strip ANSI/control noise and collapse blank lines to reduce token overhead.
  local file="$1"
  [[ -f "$file" ]] || return 0

  local tmp; tmp="$(ai_mktemp)"

  if command -v python3 >/dev/null 2>&1; then
    if python3 - "$file" <<'PY' >"$tmp"; then :; else rm -f "$tmp" 2>/dev/null || true; return 0; fi
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text(errors="ignore")
text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)       # CSI
text = re.sub(r'\x1b\][^\x07]*(\x07|\\)', '', text)       # OSC
text = re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '', text)      # control chars (keep \t/\n)

clean = []
for line in (ln.rstrip() for ln in text.splitlines()):
    if line.strip() == '':
        if clean and clean[-1] == '':
            continue
        clean.append('')
    else:
        clean.append(line)

out = "\n".join(clean).strip()
if out:
    sys.stdout.write(out + "\n")
PY
  elif command -v perl >/dev/null 2>&1; then
    perl -pe 's/\e\[[0-?]*[ -/]*[@-~]//g; s/\e\][^\a]*(\a|\\)//g; s/[\x00-\x08\x0b-\x1f\x7f]//g' "$file" >"$tmp" 2>/dev/null || true
  else
    sed -E 's/\x1B\[[0-?]*[ -/]*[@-~]//g; s/\x1B\][^\a]*\a//g' "$file" 2>/dev/null | tr -d '\000-\010\013\014\016-\037\177' >"$tmp" 2>/dev/null || true
  fi

  mv "$tmp" "$file" 2>/dev/null || cp "$tmp" "$file"
}

ai_stat_mtime(){
  local f="$1"
  if ai_is_macos; then stat -f %m "$f" 2>/dev/null || echo 0
  else stat -c %Y "$f" 2>/dev/null || echo 0
  fi
}

ai_latest_file(){
  local dir="$1" pattern="$2"
  ls -t "$dir"/$pattern 2>/dev/null | head -n 1 || true
}

ai_json_get(){
  # Extract a single JSON field value from a file
  # Usage: ai_json_get file.json "key" "default"
  local file="$1" key="$2" default="${3:-}"

  if ai_cmd jq; then
    jq -r ".${key} // \"${default}\"" "$file" 2>/dev/null || echo "$default"
  else
    local line val
    line="$(grep -E "\"$key\"[[:space:]]*:" "$file" | head -n 1 || true)"
    val="$(echo "$line" | sed -E 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    echo "${val:-$default}"
  fi
}

ai_json_get_multi(){
  # Extract multiple JSON fields efficiently (one file read)
  # Usage: ai_json_get_multi file.json "key1 key2 key3"
  # Prints values separated by newlines
  local file="$1" keys="$2"

  if ai_cmd jq; then
    # Build jq expression: [.key1, .key2, .key3] | @tsv
    local expr="["
    for k in $keys; do
      expr="$expr.${k},"
    done
    expr="${expr%,}] | @tsv"
    jq -r "$expr" "$file" 2>/dev/null | tr '\t' '\n'
  else
    # Fallback: single grep/awk pass to extract all fields
    local awk_prog='{'
    local i=0
    for k in $keys; do
      ((i++))
      awk_prog="${awk_prog} if (\$0 ~ /\"$k\"[[:space:]]*:/) { gsub(/.*\"$k\"[[:space:]]*:[[:space:]]*\"/, \"\"); gsub(/\".*/, \"\"); print; next; }"
    done
    awk_prog="$awk_prog }"
    awk "$awk_prog" "$file" 2>/dev/null || true
  fi
}

aictx_infer_engine_from_model(){
  # level-1: only route to the correct CLI based on model string
  local m="$1"
  m="$(echo "$m" | tr '[:upper:]' '[:lower:]')"

  # Codex models usually contain "codex"
  if [[ "$m" == *"codex"* ]]; then echo "codex"; return; fi

  # Claude models often are opus/sonnet/haiku or start with "claude"
  if [[ "$m" == "opus" || "$m" == "sonnet" || "$m" == "haiku" || "$m" == claude* ]]; then echo "claude"; return; fi

  # Gemini models typically start with "gemini"
  if [[ "$m" == gemini* ]]; then echo "gemini"; return; fi

  echo "auto"
}

aictx_finalize_base(){
  local engine="$1" model="$2" session="$3" transcript="$4"

  ai_cmd git || { ai_log "git not found; skipping $engine auto-apply"; return 0; }
  git -C "$AICTX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { ai_log "not a git repo; skipping"; return 0; }

  # Note: requires AICTX_DIR and aictx_build_finalize_prompt from caller context
  local patch finalize_prompt
  patch="$AICTX_DIR/finalizer_$(date +"%Y-%m-%d_%H-%M").diff"
  finalize_prompt="$(aictx_build_finalize_prompt "$session" "$transcript")"

  # Execute engine-specific command
  case "$engine" in
    claude)
      claude -p --model "$model" "$(cat "$finalize_prompt")" > "$patch"
      ;;
    gemini)
      gemini --model "$model" -p "$(cat "$finalize_prompt")" > "$patch"
      ;;
    *)
      ai_log "unsupported engine for finalize: $engine"
      rm -f "$finalize_prompt"
      return 1
      ;;
  esac
  rm -f "$finalize_prompt"

  [[ -s "$patch" ]] || { ai_log "empty patch; keeping $patch"; return 0; }
  if git -C "$AICTX_ROOT" apply --whitespace=nowarn "$patch"; then
    rm -f "$patch"
  else
    ai_log "patch failed, kept: $patch"
  fi
}

run_with_script_transcript() {
  local transcript="$1"; shift
  if ai_is_macos; then
    script -q "$transcript" "$@"
  else
    if script -q "$transcript" "$@" >/dev/null 2>&1; then :; else
      script -q -c "$(printf '%q ' "$@")" "$transcript"
    fi
  fi
  ai_sanitize_transcript "$transcript"
}

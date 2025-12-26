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

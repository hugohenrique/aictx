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
text = re.sub(r'\x1b\][^\a]*(\x07|\\)', '', text)       # OSC
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

ai_compress_transcript(){
  # Phase 3: Intelligent transcript compression for token optimization
  # Requires Python 3 for advanced processing
  local file="$1"
  [[ -f "$file" ]] || return 0

  command -v python3 >/dev/null 2>&1 || { ai_log "Python3 not found, skipping compression"; return 0; }

  local tmp; tmp="$(ai_mktemp)"

  python3 - "$file" <<'PY' >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 0; }
import re, sys, pathlib
from collections import defaultdict

path = pathlib.Path(sys.argv[1])
text = path.read_text(errors="ignore")
lines = text.splitlines()

# Layer 1: Identify command patterns (read-only vs write operations)
readonly_cmds = {'ls', 'cat', 'head', 'tail', 'grep', 'find', 'git status', 'git log', 'git diff', 'pwd', 'which', 'echo'}

# Layer 2: Track repeated errors/warnings
error_counts = defaultdict(int)
error_pattern = re.compile(r'(error|ERROR|Error|warning|WARNING|Warning|failed|FAILED|Failed):\s*(.+)')

# Layer 3: Track duplicate tool outputs
last_readonly_cmd = {}
compressed = []
consecutive_empty = 0

i = 0
while i < len(lines):
    line = lines[i].strip()

    # Skip excessive blank lines
    if not line:
        consecutive_empty += 1
        if consecutive_empty <= 2:
            compressed.append('')
        i += 1
        continue

    consecutive_empty = 0

    # Detect command execution (common patterns)
    is_cmd = line.startswith('$') or line.startswith('>') or line.startswith('#')

    # Layer 2: Collapse repeated errors
    error_match = error_pattern.search(line)
    if error_match:
        error_key = error_match.group(2)[:100]  # First 100 chars of error
        error_counts[error_key] += 1
        if error_counts[error_key] == 1:
            compressed.append(lines[i])
        elif error_counts[error_key] == 2:
            # Replace previous with counted version
            for j in range(len(compressed) - 1, -1, -1):
                if error_key in compressed[j]:
                    compressed[j] += f" (repeated 2x)"
                    break
        else:
            # Update count
            for j in range(len(compressed) - 1, -1, -1):
                if error_key in compressed[j] and 'repeated' in compressed[j]:
                    compressed[j] = re.sub(r'\(repeated \d+x\)', f'(repeated {error_counts[error_key]}x)', compressed[j])
                    break
        i += 1
        continue

    # Layer 3: Deduplicate readonly command outputs
    if is_cmd:
        cmd_text = line.lstrip('$>#').strip()
        is_readonly = any(cmd_text.startswith(c) for c in readonly_cmds)

        if is_readonly:
            # Collect output for this command
            output_start = i + 1
            output_lines = []
            j = i + 1
            while j < len(lines) and not (lines[j].strip().startswith('$') or lines[j].strip().startswith('>')):
                output_lines.append(lines[j])
                j += 1

            output_hash = hash('\n'.join(output_lines[:50]))  # Hash first 50 lines

            if cmd_text in last_readonly_cmd and last_readonly_cmd[cmd_text] == output_hash:
                # Skip duplicate readonly output
                compressed.append(f"{lines[i]} # [output omitted - unchanged from previous run]")
                i = j
                continue
            else:
                last_readonly_cmd[cmd_text] = output_hash

    # Layer 4: Truncate very long outputs (npm install, etc)
    if not is_cmd and i > 0:
        # Look ahead to see if this is a very long output block
        block_start = i
        block_lines = 0
        j = i
        while j < len(lines) and not (lines[j].strip().startswith('$') or lines[j].strip().startswith('>')):
            if lines[j].strip():
                block_lines += 1
            j += 1

        # If block is > 100 lines, summarize middle
        if block_lines > 100:
            # Keep first 20 and last 20 lines
            for k in range(i, min(i + 20, j)):
                compressed.append(lines[k])
            compressed.append(f"\n... [{block_lines - 40} lines omitted] ...\n")
            for k in range(max(j - 20, i + 20), j):
                compressed.append(lines[k])
            i = j
            continue

    compressed.append(lines[i])
    i += 1

output = '\n'.join(compressed).strip()
if output:
    sys.stdout.write(output + '\n')
PY

  if [[ -f "$tmp" && -s "$tmp" ]]; then
    mv "$tmp" "$file" 2>/dev/null || cp "$tmp" "$file"
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
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
  ai_compress_transcript "$transcript"  # Phase 3: intelligent compression
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

# Resolve templates from the new grouped layout first, then fallback to legacy paths.
aictx_template_path(){
  local group="$1" name="$2"
  local grouped="$AICTX_HOME/templates/$group/$name"
  local legacy="$AICTX_HOME/templates/$name"

  if [[ -f "$grouped" ]]; then
    echo "$grouped"
  else
    echo "$legacy"
  fi
}

aictx_template_fill(){
  local template="$1"
  local output="$2"
  shift 2

  local env_args=()
  local kv key value
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    env_args+=("__TMPL_${key}=${value}")
  done

  env_args+=("__AICTX_ROOT=$AICTX_ROOT")
  env_args+=("__AICTX_CONTEXT=$(cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true)")

  if command -v python3 >/dev/null 2>&1; then
    env "${env_args[@]}" python3 - "$template" "$output" <<'PY'
import os
import sys
from pathlib import Path

template = Path(sys.argv[1]).read_text()
replacements = {k[7:]: v for k, v in os.environ.items() if k.startswith("__TMPL_")}
replacements["ROOT"] = os.environ.get("__AICTX_ROOT", "")
context = os.environ.get("__AICTX_CONTEXT")
if context is not None:
    replacements["CONTEXT"] = context

for key, val in replacements.items():
    template = template.replace(f"{{{{{key}}}}}", val)

Path(sys.argv[2]).write_text(template)
PY
  else
    cat <<TPL > "$output"
$(cat "$template")
TPL
  fi
}

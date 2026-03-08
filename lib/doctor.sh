#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./skill_runtime.sh
source "${AICTX_HOME}/lib/skill_runtime.sh"

aictx_doctor(){
  aictx_paths_init
  echo "root:         $AICTX_ROOT"
  echo "context dir:  $AICTX_DIR"
  echo "aictx:        $(command -v aictx >/dev/null 2>&1 && echo yes || echo no)"
  echo "codex:        $(command -v codex >/dev/null 2>&1 && echo yes || echo no)"
  echo "claude:       $(command -v claude >/dev/null 2>&1 && echo yes || echo no)"
  echo "gemini:       $(command -v gemini >/dev/null 2>&1 && echo yes || echo no)"
  echo "git:          $(command -v git >/dev/null 2>&1 && echo yes || echo no)"
  echo "script:       $(command -v script >/dev/null 2>&1 && echo yes || echo no)"
  echo "realpath:     $(command -v realpath >/dev/null 2>&1 && echo yes || echo no)"
  echo "python3:      $(command -v python3 >/dev/null 2>&1 && echo yes || echo no)"
  if aictx_skills_lint; then
    echo "skills lint:  ok"
  else
    echo "skills lint:  failed"
  fi
}

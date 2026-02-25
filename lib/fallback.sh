#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_pending_update_engine(){
  local pending="$1" engine="$2" model="$3" transcript="$4"
  [[ -f "$pending" ]] || return 1
  if ! command -v python3 >/dev/null 2>&1; then
    ai_log "fallback: python3 missing; cannot update pending metadata"
    return 1
  fi

  python3 - "$pending" "$engine" "$model" "$transcript" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
if not path.exists():
    sys.exit(0)
data = json.loads(path.read_text())
data["engine"] = sys.argv[2]
data["model"] = sys.argv[3]
data["transcript"] = sys.argv[4]
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

aictx_detect_quota_failure(){
  local transcript="$1"
  [[ -f "$transcript" ]] || return 1
  if grep -Eqi '429|quota|rate limit|too many requests' "$transcript"; then
    return 0
  fi
  return 1
}

aictx_fallback_enabled(){
  [[ "${AICTX_FALLBACK_ON_QUOTA:-false}" == "true" ]] && [[ -n "${AICTX_FALLBACK_ENGINE:-}" ]]
}

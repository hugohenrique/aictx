#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_skills_defaults(){
  export AICTX_SKILLS_ENABLED="true"
  export AICTX_SKILLS_AUTO_SELECT="true"
  export AICTX_SKILLS_MAX_ACTIVE="2"
}

aictx_skills_load_config(){
  local cfg="$AICTX_CONFIG_FILE"
  aictx_skills_defaults

  [[ -f "$cfg" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local parsed
  parsed="$(python3 - "$cfg" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    print("true|true|2")
    raise SystemExit(0)

skills = data.get("skills", {})
enabled = "true" if skills.get("enabled", True) else "false"
auto_select = "true" if skills.get("auto_select", True) else "false"
max_active = skills.get("max_active", 2)
try:
    max_active = int(max_active)
except Exception:
    max_active = 2
if max_active < 1:
    max_active = 1
print(f"{enabled}|{auto_select}|{max_active}")
PY
)"
  IFS='|' read -r AICTX_SKILLS_ENABLED AICTX_SKILLS_AUTO_SELECT AICTX_SKILLS_MAX_ACTIVE <<< "$parsed"
  export AICTX_SKILLS_ENABLED AICTX_SKILLS_AUTO_SELECT AICTX_SKILLS_MAX_ACTIVE
}

aictx_skill_dirs(){
  local dirs=("$AICTX_DIR/skills" "$AICTX_HOME/skills/v1")
  local out=()
  local d
  for d in "${dirs[@]}"; do
    [[ -d "$d" ]] && out+=("$d")
  done
  printf '%s\n' "${out[@]}"
}

aictx_skill_dir_for_id(){
  local skill_id="$1"
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/$skill_id/SKILL.json" && -f "$d/$skill_id/OVERLAY.md" ]]; then
      echo "$d/$skill_id"
      return 0
    fi
  done < <(aictx_skill_dirs)
  return 1
}

aictx_skill_intent_map_default(){
  case "$1" in
    impl) echo "triage,impl" ;;
    review) echo "triage,review-critical" ;;
    tests) echo "triage,test-strategy" ;;
    release) echo "triage,release-safety" ;;
    refactor) echo "triage,refactor-safe" ;;
    debug) echo "triage,debug-root-cause" ;;
    finalize) echo "memory-hygiene" ;;
    compact) echo "token-budget-guard" ;;
    *) echo "" ;;
  esac
}

aictx_skill_map_from_config(){
  local intent="$1"
  command -v python3 >/dev/null 2>&1 || { aictx_skill_intent_map_default "$intent"; return 0; }
  python3 - "$AICTX_CONFIG_FILE" "$intent" <<'PY'
import json
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
intent = sys.argv[2]
default = {
    "impl": ["triage", "impl"],
    "review": ["triage", "review-critical"],
    "tests": ["triage", "test-strategy"],
    "release": ["triage", "release-safety"],
    "refactor": ["triage", "refactor-safe"],
    "debug": ["triage", "debug-root-cause"],
    "finalize": ["memory-hygiene"],
    "compact": ["token-budget-guard"],
}

if not cfg.exists():
    print(",".join(default.get(intent, [])))
    raise SystemExit(0)

try:
    data = json.loads(cfg.read_text())
except Exception:
    print(",".join(default.get(intent, [])))
    raise SystemExit(0)

intent_map = data.get("skills", {}).get("intent_map", {})
mapped = intent_map.get(intent, default.get(intent, []))
if isinstance(mapped, list):
    out = [str(item).strip() for item in mapped if str(item).strip()]
elif isinstance(mapped, str):
    out = [part.strip() for part in mapped.split(",") if part.strip()]
else:
    out = default.get(intent, [])
print(",".join(out))
PY
}

aictx_skill_validate_contract(){
  local skill_id="$1"
  local skill_dir
  skill_dir="$(aictx_skill_dir_for_id "$skill_id")" || {
    ai_die "unknown skill: $skill_id"
  }

  command -v python3 >/dev/null 2>&1 || ai_die "python3 is required for skill contracts"

  python3 - "$skill_id" "$skill_dir/SKILL.json" "$skill_dir/OVERLAY.md" <<'PY'
import json
import sys
from pathlib import Path

skill_id = sys.argv[1]
skill_json = Path(sys.argv[2])
overlay = Path(sys.argv[3])

errors = []
if not skill_json.exists():
    errors.append(f"{skill_json} missing")
if not overlay.exists():
    errors.append(f"{overlay} missing")

if not errors:
    try:
        data = json.loads(skill_json.read_text())
    except Exception as exc:
        errors.append(f"{skill_json}: invalid JSON ({exc})")
        data = {}

    file_id = str(data.get("id", "")).strip()
    if file_id != skill_id:
        errors.append(f"{skill_json}: id must equal directory name '{skill_id}'")

    cap = data.get("overlay_max_lines", 40)
    try:
        cap = int(cap)
    except Exception:
        errors.append(f"{skill_json}: overlay_max_lines must be an integer")
        cap = 40

    if cap < 1:
        errors.append(f"{skill_json}: overlay_max_lines must be >= 1")
    if cap > 40:
        errors.append(f"{skill_json}: overlay_max_lines cannot exceed 40")

    for key in ("compatible_with", "incompatible_with"):
        value = data.get(key, [])
        if value is None:
            continue
        if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
            errors.append(f"{skill_json}: {key} must be a string array")

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    raise SystemExit(1)
PY
}

aictx_skill_meta(){
  local skill_id="$1" field="$2"
  local skill_dir
  skill_dir="$(aictx_skill_dir_for_id "$skill_id")" || return 1

  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$skill_dir/SKILL.json" "$field" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
data = json.loads(path.read_text())
value = data.get(field)

if isinstance(value, list):
    print(",".join(str(v).strip() for v in value if str(v).strip()))
elif value is None:
    print("")
else:
    print(str(value).strip())
PY
}

aictx_skill_overlay_text(){
  local skill_id="$1"
  local skill_dir
  skill_dir="$(aictx_skill_dir_for_id "$skill_id")" || return 1
  local cap
  cap="$(aictx_skill_meta "$skill_id" "overlay_max_lines" 2>/dev/null || echo "40")"
  [[ "$cap" =~ ^[0-9]+$ ]] || cap="40"
  (( cap > 40 )) && cap="40"
  (( cap < 1 )) && cap="1"
  head -n "$cap" "$skill_dir/OVERLAY.md"
}

aictx_skills_normalize_csv(){
  local csv="$1"
  local normalized=""
  local part
  IFS=',' read -r -a parts <<< "$csv"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$part" ]] && continue
    if [[ ",$normalized," != *",$part,"* ]]; then
      [[ -n "$normalized" ]] && normalized+=","
      normalized+="$part"
    fi
  done
  echo "$normalized"
}

aictx_skills_check_compatibility(){
  local csv="$1"
  [[ -z "$csv" ]] && return 0

  local ids=()
  local id
  IFS=',' read -r -a ids <<< "$csv"

  local i j
  for ((i=0; i<${#ids[@]}; i++)); do
    id="${ids[i]}"
    aictx_skill_validate_contract "$id"
  done

  for ((i=0; i<${#ids[@]}; i++)); do
    local lhs="${ids[i]}"
    local lhs_compat lhs_incompat
    lhs_compat="$(aictx_skill_meta "$lhs" "compatible_with" 2>/dev/null || true)"
    lhs_incompat="$(aictx_skill_meta "$lhs" "incompatible_with" 2>/dev/null || true)"

    for ((j=i+1; j<${#ids[@]}; j++)); do
      local rhs="${ids[j]}"
      local rhs_compat rhs_incompat
      rhs_compat="$(aictx_skill_meta "$rhs" "compatible_with" 2>/dev/null || true)"
      rhs_incompat="$(aictx_skill_meta "$rhs" "incompatible_with" 2>/dev/null || true)"

      if [[ -n "$lhs_incompat" && ",$lhs_incompat," == *",$rhs,"* ]]; then
        ai_die "skill pair not allowed: $lhs with $rhs"
      fi
      if [[ -n "$rhs_incompat" && ",$rhs_incompat," == *",$lhs,"* ]]; then
        ai_die "skill pair not allowed: $lhs with $rhs"
      fi
      if [[ -n "$lhs_compat" && ",$lhs_compat," != *",$rhs,"* ]]; then
        ai_die "skill $lhs is not compatible with $rhs"
      fi
      if [[ -n "$rhs_compat" && ",$rhs_compat," != *",$lhs,"* ]]; then
        ai_die "skill $rhs is not compatible with $lhs"
      fi
    done
  done
}

aictx_skills_limit_active(){
  local csv="$1"
  local max_active="${AICTX_SKILLS_MAX_ACTIVE:-2}"
  [[ "$max_active" =~ ^[0-9]+$ ]] || max_active="2"

  local ids=()
  IFS=',' read -r -a ids <<< "$csv"
  if [[ ${#ids[@]} -gt "$max_active" ]]; then
    ai_die "too many active skills (${#ids[@]} > $max_active)"
  fi
}

aictx_select_skills(){
  local intent="$1"
  local explicit_single="$2"
  local explicit_multi="$3"
  local no_skill="$4"
  local command_name="${5:-run}"
  local selected=""

  aictx_skills_load_config

  if [[ "$no_skill" == "1" || "${AICTX_SKILLS_ENABLED:-true}" != "true" ]]; then
    echo ""
    return 0
  fi

  if [[ -n "$explicit_multi" ]]; then
    selected="$explicit_multi"
  elif [[ -n "$explicit_single" ]]; then
    selected="$explicit_single"
  elif [[ -n "$intent" ]]; then
    selected="$(aictx_skill_map_from_config "$intent")"
  elif [[ "${AICTX_SKILLS_AUTO_SELECT:-true}" == "true" ]]; then
    case "$command_name" in
      review) selected="$(aictx_skill_map_from_config "review")" ;;
      swarm) selected="impl,review" ;;
      run|*) selected="$(aictx_skill_map_from_config "impl")" ;;
    esac
  fi

  selected="$(aictx_skills_normalize_csv "$selected")"
  [[ -z "$selected" ]] && { echo ""; return 0; }

  aictx_skills_limit_active "$selected"
  aictx_skills_check_compatibility "$selected"
  echo "$selected"
}

aictx_skills_overlay_block(){
  local csv="$1"
  [[ -z "$csv" ]] && return 0

  local id
  IFS=',' read -r -a ids <<< "$csv"
  for id in "${ids[@]}"; do
    echo "## Skill: $id"
    aictx_skill_overlay_text "$id"
    echo ""
  done
}

aictx_skills_lint(){
  local failed="0"
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    local skill_json
    while IFS= read -r skill_json; do
      [[ -z "$skill_json" ]] && continue
      local skill
      skill="$(basename "$(dirname "$skill_json")")"
      if ! aictx_skill_validate_contract "$skill" >/dev/null 2>&1; then
        echo "invalid skill: $skill ($(dirname "$skill_json"))" >&2
        failed="1"
      fi
    done < <(find "$d" -mindepth 2 -maxdepth 2 -type f -name "SKILL.json" | sort)
  done < <(aictx_skill_dirs)
  [[ "$failed" == "0" ]]
}

aictx_pending_get_meta(){
  local file="$1"
  [[ -f "$file" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
skills = data.get("skills", [])
if isinstance(skills, str):
    skills_csv = skills
elif isinstance(skills, list):
    skills_csv = ",".join(str(item).strip() for item in skills if str(item).strip())
else:
    skills_csv = ""
print("|".join([
    str(data.get("engine", "")),
    str(data.get("model", "")),
    str(data.get("session", "")),
    str(data.get("transcript", "")),
    skills_csv,
    str(data.get("intent", "")),
]))
PY
}

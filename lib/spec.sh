#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./bootstrap.sh
source "${AICTX_HOME}/lib/bootstrap.sh"
# shellcheck source=./spec_kit.sh
source "${AICTX_HOME}/lib/spec_kit.sh"
# shellcheck source=./template.sh
source "${AICTX_HOME}/lib/template.sh"

aictx_constitution_usage(){
  cat <<EOF
Usage: aictx constitution [init]

Initialize or repair the active constitution file for the current spec layout.
EOF
}

aictx_specify_usage(){
  cat <<EOF
Usage: aictx specify <slug>

Create a feature workspace under the active specs directory with spec/plan/tasks artifacts.
EOF
}

aictx_analyze_usage(){
  cat <<EOF
Usage: aictx analyze <slug>

Validate consistency and coverage across spec.md, plan.md, and tasks.md.
EOF
}

aictx_spec_slug_normalize(){
  local input="${1:-}"
  input="$(echo "$input" | tr '[:upper:]' '[:lower:]')"
  input="$(echo "$input" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  echo "$input"
}

aictx_spec_title_from_slug(){
  local slug="$1"
  slug="$(echo "$slug" | sed -E 's/^[0-9]+-?//')"
  slug="${slug//-/ }"
  [[ -n "$slug" ]] || slug="Untitled spec"
  printf '%s\n' "$slug"
}

aictx_spec_bootstrap(){
  aictx_paths_init
  aictx_bootstrap
  mkdir -p "$(aictx_spec_kit_specs_target)"
}

aictx_spec_dir(){
  local slug="$1"
  echo "$(aictx_spec_kit_specs_target)/$slug"
}

aictx_spec_file(){
  local slug="$1" name="$2"
  echo "$(aictx_spec_dir "$slug")/$name"
}

aictx_spec_exists(){
  local slug="$1"
  [[ -d "$(aictx_spec_dir "$slug")" ]]
}

aictx_spec_assert_exists(){
  local slug="$1"
  [[ -n "$slug" ]] || ai_die "spec slug is required"
  aictx_paths_init
  [[ -d "$AICTX_DIR" ]] || ai_die "no .aictx/ found in this project. Run: aictx init"
  aictx_spec_exists "$slug" || ai_die "spec not found: $slug"
}

aictx_spec_primary_files(){
  local slug="$1"
  local files=()
  local constitution_file
  constitution_file="$(aictx_spec_kit_constitution_target)"
  [[ -f "$constitution_file" ]] && files+=("$constitution_file")
  local name
  for name in spec.md plan.md tasks.md; do
    [[ -f "$(aictx_spec_file "$slug" "$name")" ]] && files+=("$(aictx_spec_file "$slug" "$name")")
  done
  printf '%s\n' "${files[@]}"
}

aictx_spec_context_files(){
  local slug="$1"
  [[ -n "$slug" ]] || return 0
  local files=()
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(aictx_spec_primary_files "$slug")

  local name
  for name in research.md data-model.md quickstart.md; do
    [[ -f "$(aictx_spec_file "$slug" "$name")" ]] && files+=("$(aictx_spec_file "$slug" "$name")")
  done

  local extra_dir
  for extra_dir in contracts checklists; do
    if [[ -d "$(aictx_spec_dir "$slug")/$extra_dir" ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
      done < <(find "$(aictx_spec_dir "$slug")/$extra_dir" -type f | sort)
    fi
  done

  printf '%s\n' "${files[@]}"
}

aictx_spec_paths_label(){
  local slug="$1"
  [[ -n "$slug" ]] || { echo "none"; return 0; }
  local out=""
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -n "$out" ]] && out+=" "
    out+="${f#$AICTX_ROOT/}"
  done < <(aictx_spec_context_files "$slug")
  echo "${out:-none}"
}

aictx_spec_inline_block(){
  local slug="$1"
  [[ -n "$slug" ]] || return 0
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    printf '## %s\n' "${f#$AICTX_ROOT/}"
    cat "$f"
    printf '\n\n'
  done < <(aictx_spec_primary_files "$slug")
}

aictx_spec_init(){
  aictx_spec_bootstrap
  local constitution_file
  constitution_file="$(aictx_spec_kit_constitution_target)"
  mkdir -p "$(dirname "$constitution_file")"
  [[ -f "$constitution_file" ]] || cp "$(aictx_spec_kit_template_path "constitution.md")" "$constitution_file"
  ai_log "constitution/spec workspace ready: $(aictx_spec_kit_specs_target)"
}

aictx_spec_create(){
  local raw_slug="${1:-}"
  [[ -n "$raw_slug" ]] || ai_die "usage: aictx specify <slug>"

  aictx_spec_bootstrap

  local slug title spec_dir
  slug="$(aictx_spec_slug_normalize "$raw_slug")"
  [[ -n "$slug" ]] || ai_die "invalid spec slug: $raw_slug"
  title="$(aictx_spec_title_from_slug "$slug")"
  spec_dir="$(aictx_spec_dir "$slug")"

  [[ ! -e "$spec_dir" ]] || ai_die "spec already exists: $slug"

  mkdir -p "$spec_dir/contracts" "$spec_dir/checklists"

  aictx_template_fill "$(aictx_spec_kit_template_path "spec.md")" "$(aictx_spec_file "$slug" "spec.md")" \
    "SLUG=$slug" \
    "TITLE=$title"
  aictx_template_fill "$(aictx_spec_kit_template_path "plan.md")" "$(aictx_spec_file "$slug" "plan.md")" \
    "SLUG=$slug" \
    "TITLE=$title"
  aictx_template_fill "$(aictx_spec_kit_template_path "tasks.md")" "$(aictx_spec_file "$slug" "tasks.md")" \
    "SLUG=$slug" \
    "TITLE=$title"
  aictx_template_fill "$(aictx_spec_kit_template_path "meta.json")" "$(aictx_spec_file "$slug" "meta.json")" \
    "SLUG=$slug" \
    "TITLE=$title"

  ai_log "spec created: $spec_dir"
}

aictx_spec_show(){
  local slug="${1:-}"
  [[ -n "$slug" ]] || ai_die "usage: aictx specify <slug>"
  aictx_spec_assert_exists "$slug"

  local spec_dir
  spec_dir="$(aictx_spec_dir "$slug")"
  echo "slug: $slug"
  echo "dir: $spec_dir"
  echo "constitution: $(aictx_spec_kit_constitution_target)"
  echo "files:"
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] && echo "  - ${f#$AICTX_ROOT/}"
  done < <(aictx_spec_context_files "$slug")
}

aictx_spec_analyze(){
  local slug="${1:-}"
  [[ -n "$slug" ]] || ai_die "usage: aictx analyze <slug>"
  aictx_spec_assert_exists "$slug"

  local failures=0
  local required=(
    "$(aictx_spec_kit_constitution_target)"
    "$(aictx_spec_file "$slug" "spec.md")"
    "$(aictx_spec_file "$slug" "plan.md")"
    "$(aictx_spec_file "$slug" "tasks.md")"
    "$(aictx_spec_file "$slug" "meta.json")"
  )
  local f
  for f in "${required[@]}"; do
    if [[ -f "$f" ]]; then
      echo "[OK] ${f#$AICTX_ROOT/}"
    else
      echo "[FAIL] missing ${f#$AICTX_ROOT/}"
      failures=$((failures + 1))
    fi
  done

  if [[ -f "$(aictx_spec_file "$slug" "meta.json")" ]]; then
    if grep -q "\"slug\": \"$slug\"" "$(aictx_spec_file "$slug" "meta.json")"; then
      echo "[OK] meta.json slug matches"
    else
      echo "[FAIL] meta.json slug mismatch"
      failures=$((failures + 1))
    fi
  fi

  for f in "$(aictx_spec_file "$slug" "spec.md")" "$(aictx_spec_file "$slug" "plan.md")" "$(aictx_spec_file "$slug" "tasks.md")"; do
    if grep -q '{{[A-Z_][A-Z_]*}}' "$f"; then
      echo "[FAIL] unresolved template marker in ${f#$AICTX_ROOT/}"
      failures=$((failures + 1))
    else
      echo "[OK] no template markers in ${f#$AICTX_ROOT/}"
    fi
  done

  if command -v python3 >/dev/null 2>&1; then
    local analysis_output analysis_status
    if analysis_output="$(python3 - "$(aictx_spec_file "$slug" "spec.md")" "$(aictx_spec_file "$slug" "plan.md")" "$(aictx_spec_file "$slug" "tasks.md")" <<'PY'
import re
import sys
from pathlib import Path

spec_path = Path(sys.argv[1])
plan_path = Path(sys.argv[2])
tasks_path = Path(sys.argv[3])

spec_text = spec_path.read_text()
plan_text = plan_path.read_text()
tasks_text = tasks_path.read_text()

failures = 0
warnings = 0

def emit(status, msg):
    print(f"[{status}] {msg}")

req_ids = re.findall(r'^\s*-\s*\[(R\d+)\]\s+.+$', spec_text, re.MULTILINE)
ac_ids = re.findall(r'^\s*-\s*\[\s*[xX ]?\s*\]\s*\[(AC\d+)\]\s+.+$', spec_text, re.MULTILINE)
task_refs = set(re.findall(r'\[(R\d+|AC\d+)\]', tasks_text))
task_lines = [line.strip() for line in tasks_text.splitlines() if re.match(r'^\s*-\s*\[[ xX]\]\s+', line)]
validation_lines = [line.strip() for line in plan_text.splitlines() if line.strip().startswith('- ')]

if req_ids:
    emit("OK", f"requirements found: {', '.join(req_ids)}")
else:
    emit("FAIL", "spec.md has no requirement identifiers like [R1]")
    failures += 1

if ac_ids:
    emit("OK", f"acceptance criteria found: {', '.join(ac_ids)}")
else:
    emit("FAIL", "spec.md has no acceptance criteria identifiers like [AC1]")
    failures += 1

for req_id in req_ids:
    if req_id in task_refs:
        emit("OK", f"tasks cover requirement {req_id}")
    else:
        emit("FAIL", f"tasks.md does not reference requirement {req_id}")
        failures += 1

for ac_id in ac_ids:
    if ac_id in task_refs:
        emit("OK", f"tasks cover acceptance criterion {ac_id}")
    else:
        emit("FAIL", f"tasks.md does not reference acceptance criterion {ac_id}")
        failures += 1

testish = [line for line in task_lines if re.search(r'\b(test|tests|validate|validation|check|checks)\b', line, re.IGNORECASE)]
if testish:
    emit("OK", f"test or validation tasks found: {len(testish)}")
else:
    emit("FAIL", "tasks.md is missing explicit test or validation tasks")
    failures += 1

plan_checks = {
    "unit tests": any("unit tests:" in line.lower() for line in validation_lines),
    "integration tests": any("integration tests:" in line.lower() for line in validation_lines),
    "manual verification": any("manual verification:" in line.lower() for line in validation_lines),
}

for label, present in plan_checks.items():
    if present:
        emit("OK", f"plan validation covers {label}")
    else:
        emit("WARN", f"plan validation is missing {label}")
        warnings += 1

if warnings:
    emit("WARN", f"analysis warnings: {warnings}")
if failures:
    emit("FAIL", f"analysis failures: {failures}")
    raise SystemExit(1)
emit("OK", "cross-file coverage checks passed")
PY
)"; then
      printf '%s\n' "$analysis_output"
    else
      analysis_status=$?
      printf '%s\n' "$analysis_output"
      failures=$((failures + 1))
    fi
  else
    echo "[WARN] python3 unavailable; skipped requirement/task/test coverage analysis"
  fi

  if [[ "$failures" -gt 0 ]]; then
    ai_log "spec analyze failed with $failures issue(s)"
    return 1
  fi

  ai_log "spec analyze passed"
}

aictx_spec(){
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    -h|--help|"")
      ai_log "warning: 'aictx spec' is a legacy alias; prefer 'aictx constitution', 'aictx specify', and 'aictx analyze'."
      aictx_spec_usage
      ;;
    init) aictx_spec_init "$@" ;;
    create) aictx_spec_create "$@" ;;
    show) aictx_spec_show "$@" ;;
    analyze) aictx_spec_analyze "$@" ;;
    *) ai_die "unknown spec command: $cmd" ;;
  esac
}

aictx_constitution(){
  local cmd="${1:-init}"
  case "$cmd" in
    -h|--help) aictx_constitution_usage ;;
    init|"")
      aictx_spec_init
      ;;
    *)
      ai_die "unknown arg for constitution: $cmd (use: aictx constitution [init])"
      ;;
  esac
}

aictx_specify(){
  local slug="${1:-}"
  [[ -n "$slug" ]] || { aictx_specify_usage; return 1; }
  aictx_spec_create "$slug"
}

aictx_analyze(){
  local slug="${1:-}"
  [[ -n "$slug" ]] || { aictx_analyze_usage; return 1; }
  aictx_spec_analyze "$slug"
}

# Legacy alias kept for compatibility with the earlier MVP.
aictx_spec_usage(){
  cat <<EOF
Usage:
  aictx constitution [init]
  aictx specify <slug>
  aictx analyze <slug>
EOF
}

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"

aictx_skill_usage(){
  cat <<EOF
Usage: aictx skill <subcommand> [options]

Subcommands:
  install <repo|url> [--ref <git-ref>] [--force] [--dry-run]
  validate <repo|url|path> [--ref <git-ref>]
  list
  remove <skill-id>

Examples:
  aictx skill install owner/repo
  aictx skill install https://github.com/owner/repo --ref v1.0.0
  aictx skill validate owner/repo
  aictx skill list
  aictx skill remove triage
EOF
}

aictx_skill_repo_to_url(){
  local input="$1"
  if [[ "$input" == https://github.com/* || "$input" == git@github.com:* ]]; then
    echo "$input"
    return
  fi
  if [[ "$input" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "https://github.com/$input.git"
    return
  fi
  ai_die "invalid repository format: $input (use owner/repo or GitHub URL)"
}

aictx_skill_validate_tree(){
  local root="$1"
  command -v python3 >/dev/null 2>&1 || ai_die "python3 is required for skill validation"
  python3 - "$root" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
if not root.exists():
    print(f"path not found: {root}", file=sys.stderr)
    raise SystemExit(1)

MAX_FILES = 300
MAX_BYTES = 5 * 1024 * 1024
allowed_ext = {".md", ".json", ".txt", ".png", ".jpg", ".jpeg", ".webp", ".svg"}

files = [p for p in root.rglob("*") if p.is_file() or p.is_symlink()]
if len(files) > MAX_FILES:
    print(f"too many files ({len(files)} > {MAX_FILES})", file=sys.stderr)
    raise SystemExit(1)

total_bytes = 0
for p in files:
    if p.is_symlink():
        target = p.resolve()
        if not str(target).startswith(str(root)):
            print(f"forbidden symlink outside tree: {p}", file=sys.stderr)
            raise SystemExit(1)
        continue
    if p.suffix.lower() not in allowed_ext:
        print(f"forbidden extension: {p}", file=sys.stderr)
        raise SystemExit(1)
    total_bytes += p.stat().st_size

if total_bytes > MAX_BYTES:
    print(f"repository too large ({total_bytes} bytes > {MAX_BYTES})", file=sys.stderr)
    raise SystemExit(1)

candidates = []

# Pattern A: repo root is a single skill
if (root / "SKILL.json").exists() and (root / "OVERLAY.md").exists():
    candidates.append(root)

# Pattern B: skills/v1/<id> layout
v1 = root / "skills" / "v1"
if v1.is_dir():
    for d in sorted(v1.iterdir()):
        if d.is_dir() and (d / "SKILL.json").exists() and (d / "OVERLAY.md").exists():
            candidates.append(d)

# Pattern C: direct child folders
for d in sorted(root.iterdir()):
    if d.is_dir() and (d / "SKILL.json").exists() and (d / "OVERLAY.md").exists():
        candidates.append(d)

seen = set()
deduped = []
for d in candidates:
    k = str(d.resolve())
    if k not in seen:
        seen.add(k)
        deduped.append(d)
candidates = deduped

if not candidates:
    print("no valid skills found (expected SKILL.json + OVERLAY.md)", file=sys.stderr)
    raise SystemExit(1)

slug_re = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
for skill_dir in candidates:
    skill_json = skill_dir / "SKILL.json"
    try:
        data = json.loads(skill_json.read_text())
    except Exception as exc:
        print(f"invalid JSON: {skill_json} ({exc})", file=sys.stderr)
        raise SystemExit(1)

    skill_id = str(data.get("id", "")).strip()
    if not skill_id:
        print(f"missing id in {skill_json}", file=sys.stderr)
        raise SystemExit(1)
    if not slug_re.match(skill_id):
        print(f"invalid id '{skill_id}' in {skill_json}", file=sys.stderr)
        raise SystemExit(1)
    if skill_dir.name != skill_id:
        print(f"directory '{skill_dir.name}' must match id '{skill_id}'", file=sys.stderr)
        raise SystemExit(1)

    for field in ("name", "description"):
        if not str(data.get(field, "")).strip():
            print(f"missing or empty '{field}' in {skill_json}", file=sys.stderr)
            raise SystemExit(1)

for d in candidates:
    print(str(d.resolve()))
PY
}

aictx_skill_fetch_repo(){
  local repo_input="$1" ref="$2" out_dir="$3"
  local repo_url
  repo_url="$(aictx_skill_repo_to_url "$repo_input")"

  ai_cmd git || ai_die "git is required to install skills from repository"
  git clone --depth 1 "$repo_url" "$out_dir" >/dev/null 2>&1 || ai_die "failed to clone repository: $repo_input"
  if [[ -n "$ref" ]]; then
    git -C "$out_dir" fetch --depth 1 origin "$ref" >/dev/null 2>&1 || ai_die "failed to fetch ref: $ref"
    git -C "$out_dir" checkout -q FETCH_HEAD >/dev/null 2>&1 || ai_die "failed to checkout ref: $ref"
  fi
}

aictx_skill_install_copy(){
  local source_dir="$1" force="$2" dry_run="$3"
  local skill_id
  skill_id="$(python3 - "$source_dir/SKILL.json" <<'PY'
import json,sys
print(str(json.loads(open(sys.argv[1]).read()).get("id","")).strip())
PY
)"
  [[ -n "$skill_id" ]] || ai_die "could not resolve skill id from $source_dir/SKILL.json"

  local target_base="$AICTX_DIR/skills"
  local target_dir="$target_base/$skill_id"
  mkdir -p "$target_base"

  if [[ -d "$target_dir" && "$force" != "1" ]]; then
    ai_die "skill already exists: $skill_id (use --force)"
  fi

  if [[ "$dry_run" == "1" ]]; then
    ai_log "validated skill: $skill_id from $source_dir"
    return 0
  fi

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
  ai_log "installed skill: $skill_id -> $target_dir"
}

aictx_skill_install(){
  local repo_input="$1" ref="$2" force="$3" dry_run="$4"
  aictx_paths_init

  local tmp
  tmp="$(ai_mktemp)"
  rm -f "$tmp"
  mkdir -p "$tmp"
  trap 'rm -rf "$tmp"' RETURN

  aictx_skill_fetch_repo "$repo_input" "$ref" "$tmp/repo"

  local skill_paths
  skill_paths="$(aictx_skill_validate_tree "$tmp/repo")"
  [[ -n "$skill_paths" ]] || ai_die "no installable skill found"

  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    aictx_skill_install_copy "$p" "$force" "$dry_run"
  done <<< "$skill_paths"
}

aictx_skill_validate_input(){
  local input="$1" ref="$2"
  aictx_paths_init
  local target="$input"
  local tmp=""

  if [[ -d "$input" ]]; then
    :
  else
    tmp="$(ai_mktemp)"
    rm -f "$tmp"
    mkdir -p "$tmp"
    aictx_skill_fetch_repo "$input" "$ref" "$tmp/repo"
    target="$tmp/repo"
  fi

  local out
  out="$(aictx_skill_validate_tree "$target")"
  echo "$out" | sed 's/^/valid skill: /'
  [[ -n "$tmp" ]] && rm -rf "$tmp"
}

aictx_skill_list(){
  aictx_paths_init
  local skills_dir="$AICTX_DIR/skills"
  [[ -d "$skills_dir" ]] || { echo "no installed skills in $skills_dir"; return 0; }

  local found="0"
  local d
  for d in "$skills_dir"/*; do
    [[ -d "$d" && -f "$d/SKILL.json" ]] || continue
    found="1"
    python3 - "$d/SKILL.json" <<'PY'
import json,sys
data=json.loads(open(sys.argv[1]).read())
print(f"{data.get('id','unknown')} - {data.get('name','')}")
PY
  done
  [[ "$found" == "1" ]] || echo "no installed skills in $skills_dir"
}

aictx_skill_remove(){
  local skill_id="$1"
  aictx_paths_init
  local target="$AICTX_DIR/skills/$skill_id"
  [[ -d "$target" ]] || ai_die "skill not installed: $skill_id"
  rm -rf "$target"
  ai_log "removed skill: $skill_id"
}

aictx_skill_cmd(){
  local sub="${1:-}"
  [[ -n "$sub" ]] || { aictx_skill_usage; return 0; }
  shift || true

  case "$sub" in
    install)
      local repo="" ref="" force="0" dry_run="0"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --ref) ref="${2:-}"; shift 2 ;;
          --force) force="1"; shift 1 ;;
          --dry-run) dry_run="1"; shift 1 ;;
          -h|--help) aictx_skill_usage; return 0 ;;
          *)
            if [[ -z "$repo" ]]; then repo="$1"; shift 1
            else ai_die "unexpected arg: $1"
            fi
            ;;
        esac
      done
      [[ -n "$repo" ]] || ai_die "missing repository argument"
      aictx_skill_install "$repo" "$ref" "$force" "$dry_run"
      ;;
    validate)
      local input="" ref=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --ref) ref="${2:-}"; shift 2 ;;
          -h|--help) aictx_skill_usage; return 0 ;;
          *)
            if [[ -z "$input" ]]; then input="$1"; shift 1
            else ai_die "unexpected arg: $1"
            fi
            ;;
        esac
      done
      [[ -n "$input" ]] || ai_die "missing repository or path argument"
      aictx_skill_validate_input "$input" "$ref"
      ;;
    list)
      aictx_skill_list
      ;;
    remove)
      [[ $# -ge 1 ]] || ai_die "missing skill id"
      aictx_skill_remove "$1"
      ;;
    -h|--help|help)
      aictx_skill_usage
      ;;
    *)
      ai_die "unknown skill subcommand: $sub"
      ;;
  esac
}

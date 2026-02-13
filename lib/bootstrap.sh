#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./fs.sh
source "${AICTX_HOME}/lib/fs.sh"
# shellcheck source=./migrate.sh
source "${AICTX_HOME}/lib/migrate.sh"

AICTX_SCHEMA_CURRENT="5"

aictx_copy_if_missing(){
  local src="$1" dst="$2"
  [[ -f "$dst" ]] || cp "$src" "$dst"
}

aictx_skill_slug(){
  local input="$1"
  input="$(echo "$input" | tr '[:upper:]' '[:lower:]')"
  input="$(echo "$input" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  echo "$input"
}

aictx_init_project_skill(){
  local base slug max_base skill_name skill_dir skill_md
  base="$(basename "$AICTX_ROOT")"
  slug="$(aictx_skill_slug "$base")"
  [[ -n "$slug" ]] || slug="project"

  max_base=58
  if [[ ${#slug} -gt $max_base ]]; then
    slug="${slug:0:$max_base}"
    slug="$(echo "$slug" | sed -E 's/-+$//')"
    [[ -n "$slug" ]] || slug="project"
  fi

  skill_name="${slug}-aictx"
  skill_dir="$AICTX_DIR/skills/$skill_name"
  skill_md="$skill_dir/SKILL.md"

  [[ -f "$skill_md" ]] && return 0

  mkdir -p "$skill_dir"
  cat > "$skill_md" <<EOF
---
name: $skill_name
description: Project-specific skill for the $base repository. Use when working in this repo, updating aictx context files, or maintaining the aictx workflow for this project.
---

# $base Project Skill

## Overview
Provide context for work in this repository using the aictx memory files and current session summary.

## Context Sources
- Read files listed by the aictx paths header (always PROMPT.md and DIGEST.md; optional files only when listed).
- Keep DIGEST concise (<= 60 lines, bullets).
- Keep CONTEXT stable (<= 20 lines).
- Keep DECISIONS append-only with date headers.
- Keep TODO actionable only.

## Repository Root
- Path: $AICTX_ROOT
EOF
}

aictx_init_agents_md(){
  local file="$AICTX_ROOT/AGENTS.md"
  local marker="<!-- aictx -->"

  if [[ -f "$file" ]]; then
    grep -q "$marker" "$file" && return 0
    cat >> "$file" <<EOF

$marker
## aictx
- Follow the aictx paths header: always read PROMPT.md and DIGEST.md first.
- Read optional files only if they are listed in the header.
- Do not read older sessions unless explicitly listed.
- Keep DIGEST <= 60 lines, bullets only.
- Keep CONTEXT <= 20 lines and stable.
- Append DECISIONS with date headers.
- Keep TODO actionable only.
EOF
  else
    cat > "$file" <<EOF
$marker
## aictx
- Follow the aictx paths header: always read PROMPT.md and DIGEST.md first.
- Read optional files only if they are listed in the header.
- Do not read older sessions unless explicitly listed.
- Keep DIGEST <= 60 lines, bullets only.
- Keep CONTEXT <= 20 lines and stable.
- Append DECISIONS with date headers.
- Keep TODO actionable only.
EOF
  fi
}

aictx_init_templates(){
  mkdir -p "$AICTX_SESS_DIR" "$AICTX_TRS_DIR" "$AICTX_PENDING_DIR"

  aictx_copy_if_missing "$AICTX_HOME/templates/PROMPT.md" "$AICTX_DIR/PROMPT.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/CONTEXT.md" "$AICTX_DIR/CONTEXT.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/DECISIONS.md" "$AICTX_DIR/DECISIONS.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/TODO.md" "$AICTX_DIR/TODO.md"
  aictx_copy_if_missing "$AICTX_HOME/templates/config.json" "$AICTX_CONFIG_FILE"
  aictx_copy_if_missing "$AICTX_HOME/templates/DIGEST.md" "$AICTX_DIGEST_FILE"

  [[ -f "$AICTX_SCHEMA_FILE" ]] || echo "1" > "$AICTX_SCHEMA_FILE"
  [[ -f "$AICTX_INIT_MARK" ]] || date > "$AICTX_INIT_MARK"
}

aictx_gitignore_setup(){
  aictx_ensure_line_once ".aictx/" "$AICTX_GITIGNORE"
  aictx_ensure_line_once ".aictx/transcripts/" "$AICTX_GITIGNORE"
  aictx_ensure_line_once ".aictx/pending/" "$AICTX_GITIGNORE"
}

aictx_bootstrap(){
  aictx_paths_init
  aictx_init_templates
  aictx_init_project_skill
  aictx_init_agents_md
  aictx_gitignore_setup
  aictx_run_migrations "$AICTX_SCHEMA_CURRENT"
}

aictx_init(){
  aictx_bootstrap
  ai_log "initialized: $AICTX_DIR"
}

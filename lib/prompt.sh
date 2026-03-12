#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"
# shellcheck source=./skill_runtime.sh
source "${AICTX_HOME}/lib/skill_runtime.sh"
# shellcheck source=./context_budget.sh
source "${AICTX_HOME}/lib/context_budget.sh"
# shellcheck source=./template.sh
source "${AICTX_HOME}/lib/template.sh"
# shellcheck source=./spec.sh
source "${AICTX_HOME}/lib/spec.sh"

# Phase 3: Delta-based DIGEST optimization
aictx_snapshot_digest(){
  local digest_file="$AICTX_DIGEST_FILE"
  local snapshot_file="$AICTX_DIR/.digest_snapshot"

  [[ -f "$digest_file" ]] && cp "$digest_file" "$snapshot_file" 2>/dev/null || true
}

aictx_has_digest_snapshot(){
  [[ -f "$AICTX_DIR/.digest_snapshot" ]]
}

aictx_build_finalize_prompt(){
  local session_file="$1"
  local transcript_file="$2"
  local active_skills="${3:-${AICTX_ACTIVE_SKILLS:-}}"
  local out
  out="$(ai_mktemp)"
  local skills_label="none"
  [[ -n "$active_skills" ]] && skills_label="$active_skills"

  local use_delta=0
  local digest_diff_content=""

  if aictx_has_digest_snapshot; then
    local snapshot="$AICTX_DIR/.digest_snapshot"
    local current="$AICTX_DIGEST_FILE"

    if ! diff -q "$snapshot" "$current" >/dev/null 2>&1; then
      local digest_diff
      digest_diff=$(diff -U 1 "$snapshot" "$current" 2>/dev/null | tail -n +3 || echo "")

      if [[ -n "$digest_diff" ]]; then
        local diff_words
        diff_words=$(echo "$digest_diff" | wc -w | tr -d ' ')

        if [[ "$diff_words" -lt 15 ]]; then
          use_delta=1
          digest_diff_content="$digest_diff"
        fi
      fi
    fi
  fi

  if [[ "$use_delta" == "1" && -n "$digest_diff_content" ]]; then
    {
      echo "Output ONE git-apply diff."
      echo ""
      echo "DIGEST.md delta:"
      echo "\`\`\`diff"
      echo "$digest_diff_content"
      echo "\`\`\`"
      echo ""
      echo "Update from $transcript_file:"
      echo "- DIGEST.md: apply delta above (<=60 lines, bullets)"
      echo "- CONTEXT.md (<=20 lines, stable)"
      echo "- DECISIONS.md (append+date)"
      echo "- TODO.md (actionable)"
      echo "- $session_file (objective/done/decisions/next)"
      echo ""
      echo "Rules: no invented facts; prefer DIGEST; minimal edits."
      echo "Active skills: $skills_label"
    } > "$out"
  else
    local template
    template="$(aictx_template_path "prompts" "FINALIZE_PROMPT.md")"
    sed -e "s|{{SESSION_FILE}}|$session_file|g" \
        -e "s|{{TRANSCRIPT_FILE}}|$transcript_file|g" \
        -e "s|{{ACTIVE_SKILLS}}|$skills_label|g" \
        "$template" > "$out"
  fi

  echo "$out"
}

aictx_build_prompt(){
  local session_file="$1"
  local prev_session="$2"
  local mode="${3:-paths}"
  local active_skills="${4:-}"
  local intent="${5:-}"
  local spec_slug="${6:-}"
  local out
  out="$(ai_mktemp)"
  local skills_label="none"
  [[ -n "$active_skills" ]] && skills_label="$active_skills"
  [[ -z "$intent" ]] && intent="not specified"

  aictx_context_plan "$session_file" "$prev_session" "$mode"

  if [[ "$mode" == "inline" ]]; then
    {
      echo "# aictx inline"
      echo "COGNITIVE HIERARCHY (STRICT)"
      echo "0. User Intent"
      echo "1. Skill Policy"
      echo "2. DIGEST"
      echo "3. Active Code State"
      echo "4. Extended Memory (if needed)"
      echo "5. History (only explicit)"
      echo ""
      echo "Intent: $intent"
      echo "Active skills: $skills_label"
      [[ -n "$spec_slug" ]] && echo "Spec: $spec_slug"
      if [[ -n "$active_skills" ]]; then
        echo ""
        aictx_skills_overlay_block "$active_skills"
      fi
      cat "$AICTX_DIR/PROMPT.md"
      echo "## DIGEST.md"
      cat "$AICTX_DIGEST_FILE" 2>/dev/null || true
      if [[ "$AICTX_PLAN_LOAD_CONTEXT" == "1" ]]; then
        echo "## CONTEXT.md"
        cat "$AICTX_DIR/CONTEXT.md" 2>/dev/null || true
      fi
      if [[ "$AICTX_PLAN_LOAD_DECISIONS" == "1" ]]; then
        echo "## DECISIONS.md"
        cat "$AICTX_DIR/DECISIONS.md" 2>/dev/null || true
      fi
      if [[ "$AICTX_PLAN_LOAD_TODO" == "1" ]]; then
        echo "## TODO.md"
        cat "$AICTX_DIR/TODO.md" 2>/dev/null || true
      fi
      if [[ "$AICTX_PLAN_LOAD_PREV_SESSION" == "1" && -n "$prev_session" ]]; then
        echo "## Previous session"
        cat "$prev_session"
      fi
      if [[ -n "$spec_slug" ]]; then
        echo "## Active spec"
        aictx_spec_inline_block "$spec_slug"
      fi
      echo "## Session file to update"
      echo "$session_file"
    } > "$out"
  else
    local optional_files=""
    local prompt_rel digest_rel opt_rel session_rel spec_paths_rel

    [[ "$AICTX_PLAN_LOAD_CONTEXT" == "1" ]] && optional_files="$optional_files $AICTX_DIR/CONTEXT.md"
    [[ "$AICTX_PLAN_LOAD_DECISIONS" == "1" ]] && optional_files="$optional_files $AICTX_DIR/DECISIONS.md"
    [[ "$AICTX_PLAN_LOAD_TODO" == "1" ]] && optional_files="$optional_files $AICTX_DIR/TODO.md"
    if [[ "$AICTX_PLAN_LOAD_PREV_SESSION" == "1" && -n "$prev_session" ]]; then
      optional_files="$optional_files $prev_session"
    fi
    if [[ -n "$spec_slug" ]]; then
      local spec_file
      while IFS= read -r spec_file; do
        [[ -n "$spec_file" ]] && optional_files="$optional_files $spec_file"
      done < <(aictx_spec_context_files "$spec_slug")
    fi

    {
      echo "# aictx paths"
      echo "COGNITIVE HIERARCHY (STRICT)"
      echo "0. User Intent"
      echo "1. Skill Policy"
      echo "2. DIGEST"
      echo "3. Active Code State"
      echo "4. Extended Memory (if needed)"
      echo "5. History (only explicit)"
      echo ""
      echo "Intent: $intent"
      echo "Active skills: $skills_label"
      [[ -n "$spec_slug" ]] && echo "Spec: $spec_slug"
      if [[ -n "$active_skills" ]]; then
        echo ""
        aictx_skills_overlay_block "$active_skills"
      fi

      prompt_rel="${AICTX_DIR#$AICTX_ROOT/}/PROMPT.md"
      digest_rel="${AICTX_DIGEST_FILE#$AICTX_ROOT/}"
      opt_rel=""
      local f
      for f in $optional_files; do
        [[ -n "$opt_rel" ]] && opt_rel+=" "
        opt_rel+="${f#$AICTX_ROOT/}"
      done

      session_rel="${session_file#$AICTX_ROOT/}"
      spec_paths_rel="$(aictx_spec_paths_label "$spec_slug")"

      if [[ -n "$opt_rel" ]]; then
        echo "Read: $prompt_rel; $digest_rel first. Opt: $opt_rel${AICTX_PLAN_CONTEXT_NOTE}"
      else
        echo "Read: $prompt_rel; $digest_rel first.${AICTX_PLAN_CONTEXT_NOTE}"
      fi
      if [[ -n "$spec_slug" ]]; then
        echo "Spec files: $spec_paths_rel"
      fi
      echo "Session: $session_rel"
    } > "$out"
  fi

  echo "$out"
}

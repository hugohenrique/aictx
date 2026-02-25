#!/usr/bin/env bash
set -euo pipefail

# Namespace helpers: sessions/transcripts/pending live under .aictx/namespaces/<ns>/
ns_base_path(){
  local ns="${1:-$AICTX_NAMESPACE}"
  if [[ -n "$ns" ]]; then
    echo "$AICTX_DIR/namespaces/$ns"
  else
    echo "$AICTX_DIR"
  fi
}

ns_dir(){
  local name="$1"
  local ns="${2:-$AICTX_NAMESPACE}"
  local base
  base="$(ns_base_path "$ns")"
  echo "$base/$name"
}

ns_resolve_dir(){
  local name="$1"
  local ns="${2:-$AICTX_NAMESPACE}"
  local dir
  dir="$(ns_dir "$name" "$ns")"
  mkdir -p "$dir"
  echo "$dir"
}

ns_list(){
  local base="$AICTX_DIR/namespaces"
  [[ -d "$base" ]] || return 0
  local entry
  for entry in "$base"/*; do
    [[ -d "$entry" ]] || continue
    [[ "${entry##*/}" == "" ]] && continue
    echo "${entry##*/}"
  done
}

ns_aictx_dirs(){
  local type="$1"
  printf '%s\n' "$(ns_dir "$type" "")"
  local ns
  for ns in $(ns_list); do
    printf '%s\n' "$(ns_dir "$type" "$ns")"
  done
}

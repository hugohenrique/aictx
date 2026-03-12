#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AICTX_BIN="$REPO_ROOT/bin/aictx"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aictx-spec-kit-test.XXXXXX")"
cleanup(){
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_contains(){
  local file="$1" expected="$2"
  if ! grep -Fq "$expected" "$file"; then
    echo "assertion failed: expected '$expected' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_cmd(){
  (
    cd "$TMP_DIR/repo"
    AICTX_HOME="$REPO_ROOT" bash "$AICTX_BIN" "$@"
  )
}

mkdir -p "$TMP_DIR/repo"
(
  cd "$TMP_DIR/repo"
  git init >/dev/null
  git config user.email test@example.com
  git config user.name "aictx test"
)

run_cmd init >/tmp/aictx-spec-kit-init.out 2>/tmp/aictx-spec-kit-init.err
run_cmd spec-kit install >/tmp/aictx-spec-kit-install.out 2>/tmp/aictx-spec-kit-install.err

[[ -f "$TMP_DIR/repo/.aictx/spec-kit.json" ]]
[[ -f "$TMP_DIR/repo/.specify/memory/constitution.md" ]]
[[ -d "$TMP_DIR/repo/specs" ]]
[[ -d "$TMP_DIR/repo/.aictx/spec-kit-templates" ]]

run_cmd spec-kit status >/tmp/aictx-spec-kit-status.out
assert_contains /tmp/aictx-spec-kit-status.out "installed: yes"
assert_contains /tmp/aictx-spec-kit-status.out "mode: bundled"
assert_contains /tmp/aictx-spec-kit-status.out "active_layout: yes"
assert_contains /tmp/aictx-spec-kit-status.out "/repo/.specify/memory/constitution.md"
assert_contains /tmp/aictx-spec-kit-status.out "/repo/specs"

run_cmd specify 001-bundled-flow >/tmp/aictx-spec-kit-specify.out 2>/tmp/aictx-spec-kit-specify.err
[[ -f "$TMP_DIR/repo/specs/001-bundled-flow/spec.md" ]]
[[ -f "$TMP_DIR/repo/specs/001-bundled-flow/plan.md" ]]
[[ -f "$TMP_DIR/repo/specs/001-bundled-flow/tasks.md" ]]

run_cmd analyze 001-bundled-flow >/tmp/aictx-spec-kit-analyze.out 2>/tmp/aictx-spec-kit-analyze.err
assert_contains /tmp/aictx-spec-kit-analyze.out "[OK] .specify/memory/constitution.md"
assert_contains /tmp/aictx-spec-kit-analyze.out "[OK] specs/001-bundled-flow/spec.md"

run_cmd spec-kit uninstall >/tmp/aictx-spec-kit-uninstall.out 2>/tmp/aictx-spec-kit-uninstall.err
[[ ! -f "$TMP_DIR/repo/.aictx/spec-kit.json" ]]
[[ ! -d "$TMP_DIR/repo/.aictx/spec-kit-templates" ]]
[[ -f "$TMP_DIR/repo/.specify/memory/constitution.md" ]]
[[ -f "$TMP_DIR/repo/specs/001-bundled-flow/spec.md" ]]

run_cmd spec-kit status >/tmp/aictx-spec-kit-status-after.out
assert_contains /tmp/aictx-spec-kit-status-after.out "installed: no"
assert_contains /tmp/aictx-spec-kit-status-after.out "active_layout: yes"

echo "spec-kit functional test passed"

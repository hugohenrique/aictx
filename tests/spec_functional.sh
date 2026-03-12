#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AICTX_BIN="$REPO_ROOT/bin/aictx"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aictx-spec-test.XXXXXX")"
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

run_cmd init >/tmp/aictx-spec-init.out 2>/tmp/aictx-spec-init.err
[[ -f "$TMP_DIR/repo/.aictx/constitution.md" ]]
[[ -d "$TMP_DIR/repo/.aictx/specs" ]]

run_cmd constitution >/tmp/aictx-constitution.out 2>/tmp/aictx-constitution.err
run_cmd specify 001-login-rate-limit >/tmp/aictx-spec-create.out 2>/tmp/aictx-spec-create.err
[[ -f "$TMP_DIR/repo/.aictx/specs/001-login-rate-limit/spec.md" ]]
[[ -f "$TMP_DIR/repo/.aictx/specs/001-login-rate-limit/plan.md" ]]
[[ -f "$TMP_DIR/repo/.aictx/specs/001-login-rate-limit/tasks.md" ]]
[[ -f "$TMP_DIR/repo/.aictx/specs/001-login-rate-limit/meta.json" ]]

run_cmd analyze 001-login-rate-limit >/tmp/aictx-spec-analyze.out 2>/tmp/aictx-spec-analyze.err
assert_contains /tmp/aictx-spec-analyze.out "[OK] .aictx/specs/001-login-rate-limit/spec.md"
assert_contains /tmp/aictx-spec-analyze.out "[OK] tasks cover requirement R1"
assert_contains /tmp/aictx-spec-analyze.out "[OK] test or validation tasks found:"

run_cmd prompt-plan --spec 001-login-rate-limit > /tmp/aictx-spec-plan.out
assert_contains /tmp/aictx-spec-plan.out "Active spec: 001-login-rate-limit"
assert_contains /tmp/aictx-spec-plan.out ".aictx/specs/001-login-rate-limit/spec.md"

run_cmd stats --spec 001-login-rate-limit > /tmp/aictx-spec-stats.out
assert_contains /tmp/aictx-spec-stats.out ".aictx/constitution.md"
assert_contains /tmp/aictx-spec-stats.out ".aictx/specs/001-login-rate-limit/tasks.md"

run_cmd run --dry-run --spec 001-login-rate-limit > /tmp/aictx-spec-dry-run.out
assert_contains /tmp/aictx-spec-dry-run.out "DRY RUN: engine execution skipped."
assert_contains /tmp/aictx-spec-dry-run.out ".aictx/specs/001-login-rate-limit/plan.md"

perl -0pi -e 's/\- \[ \] \[R2\].*\n//' "$TMP_DIR/repo/.aictx/specs/001-login-rate-limit/tasks.md"
if run_cmd analyze 001-login-rate-limit >/tmp/aictx-spec-analyze-fail.out 2>/tmp/aictx-spec-analyze-fail.err; then
  echo "expected spec analyze to fail when requirement coverage is missing" >&2
  exit 1
fi
assert_contains /tmp/aictx-spec-analyze-fail.out "[FAIL] tasks.md does not reference requirement R2"

echo "spec functional test passed"

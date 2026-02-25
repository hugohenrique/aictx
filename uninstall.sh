#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uninstall aictx from a local prefix.

Usage:
  ./uninstall.sh [options]

Options:
  --prefix <dir>            install prefix (default: $HOME/.local)
  --install-dir <dir>       installation dir (default: <prefix>/share/aictx)
  --bin-dir <dir>           bin dir (default: <prefix>/bin)
  -h, --help                show this help
EOF
}

log() { printf 'aictx-uninstall: %s\n' "$*"; }

PREFIX="${HOME}/.local"
BIN_DIR=""
INSTALL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'aictx-uninstall: error: unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
done

BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
INSTALL_DIR="${INSTALL_DIR:-$PREFIX/share/aictx}"

if [[ -L "$BIN_DIR/aictx" || -f "$BIN_DIR/aictx" ]]; then
  rm -f "$BIN_DIR/aictx"
  log "removed $BIN_DIR/aictx"
fi

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  log "removed $INSTALL_DIR"
fi

log "done"

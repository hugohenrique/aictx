#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install aictx (idempotent installer)

Usage:
  ./install.sh [options]

Options:
  --upgrade                 overwrite existing installation
  --force                   same as --upgrade
  --prefix <dir>            install prefix (default: $HOME/.local)
  --install-dir <dir>       installation dir (default: <prefix>/share/aictx)
  --bin-dir <dir>           bin dir (default: <prefix>/bin)
  --from <path|url>         source path or tar.gz URL (default: current repo)
  --version <tag>           install from GitHub tag tarball
  --repo <owner/repo>       GitHub repo for --version (required with --version)
  -h, --help                show this help

Examples:
  ./install.sh
  ./install.sh --upgrade
  ./install.sh --version v0.3.0 --repo your-org/aictx
EOF
}

log() { printf 'aictx-install: %s\n' "$*"; }
die() { printf 'aictx-install: error: %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

PREFIX="${HOME}/.local"
BIN_DIR=""
INSTALL_DIR=""
FROM=""
VERSION_TAG=""
REPO=""
UPGRADE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade|--force) UPGRADE="1"; shift 1 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    --from) FROM="${2:-}"; shift 2 ;;
    --version) VERSION_TAG="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1 (use --help)" ;;
  esac
done

[[ -n "$PREFIX" ]] || die "--prefix cannot be empty"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
INSTALL_DIR="${INSTALL_DIR:-$PREFIX/share/aictx}"

if [[ -n "$VERSION_TAG" ]]; then
  [[ -n "$REPO" ]] || die "--repo is required when --version is used"
  FROM="https://github.com/${REPO}/archive/refs/tags/${VERSION_TAG}.tar.gz"
fi

need_cmd mkdir
need_cmd cp
need_cmd ln
need_cmd rm

tmp=""
cleanup() {
  [[ -n "$tmp" && -d "$tmp" ]] && rm -rf "$tmp" || true
}
trap cleanup EXIT

src_root=""
if [[ -n "$FROM" ]]; then
  if [[ "$FROM" =~ ^https?:// ]]; then
    need_cmd tar
    tmp="$(mktemp -d)"
    archive="$tmp/src.tar.gz"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$FROM" -o "$archive" || die "failed to download: $FROM"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$archive" "$FROM" || die "failed to download: $FROM"
    else
      die "curl or wget is required to download remote source"
    fi
    tar -xzf "$archive" -C "$tmp"
    src_root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$src_root" ]] || die "failed to unpack source archive"
  else
    [[ -d "$FROM" ]] || die "--from path does not exist: $FROM"
    src_root="$(cd "$FROM" && pwd)"
  fi
else
  # Local repository root (installer script directory).
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  src_root="$script_dir"
fi

[[ -f "$src_root/bin/aictx" ]] || die "invalid source: missing bin/aictx at $src_root"
[[ -d "$src_root/lib" ]] || die "invalid source: missing lib/ at $src_root"
[[ -d "$src_root/templates" ]] || die "invalid source: missing templates/ at $src_root"

if [[ -d "$INSTALL_DIR" && "$UPGRADE" != "1" ]]; then
  die "installation exists at $INSTALL_DIR (re-run with --upgrade)"
fi

log "installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/templates"
cp -R "$src_root/bin" "$INSTALL_DIR/"
cp -R "$src_root/lib" "$INSTALL_DIR/"
cp -R "$src_root/templates" "$INSTALL_DIR/"
[[ -f "$src_root/LICENSE" ]] && cp "$src_root/LICENSE" "$INSTALL_DIR/" || true
[[ -f "$src_root/README.md" ]] && cp "$src_root/README.md" "$INSTALL_DIR/" || true
[[ -f "$src_root/UX.md" ]] && cp "$src_root/UX.md" "$INSTALL_DIR/" || true

mkdir -p "$BIN_DIR"
ln -sfn "$INSTALL_DIR/bin/aictx" "$BIN_DIR/aictx"
chmod +x "$INSTALL_DIR/bin/aictx" || true

log "installed binary: $BIN_DIR/aictx"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  log "PATH does not include $BIN_DIR"
  log "add this to your shell profile:"
  printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
fi

log "done"

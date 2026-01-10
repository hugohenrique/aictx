#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./core.sh
source "${AICTX_HOME}/lib/core.sh"

aictx_install_launchd(){
  ai_is_macos || ai_die "install-launchd is macOS only"

  local label="com.${USER}.aictx.watch"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"
  local logdir="$HOME/Library/Logs/aictx"
  mkdir -p "$logdir"

  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(command -v aictx)</string>
    <string>watch</string>
    <string>--interval</string>
    <string>20</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${logdir}/watch.out.log</string>
  <key>StandardErrorPath</key><string>${logdir}/watch.err.log</string>
</dict>
</plist>
EOF

  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
  ai_log "installed launchd agent: $plist"
  ai_log "logs: $logdir"
}

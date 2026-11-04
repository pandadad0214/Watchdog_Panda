#!/usr/bin/env bash
# One-command installer for Watchdog Panda.
#   curl -fsSL https://github.com/pandadad0214/Watchdog_Panda/releases/latest/download/install.sh | bash
# Downloads the latest Release package into ${WATCHDOG_PANDA_HOME:-$HOME/watchdog-panda}.
# Works on Linux, macOS and Termux (Android). Needs bash, curl and tar.
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-${WATCHDOG_PANDA_HOME:-$HOME/watchdog-panda}}"
URL="https://github.com/pandadad0214/Watchdog_Panda/releases/latest/download/watchdog-panda.tar.gz"
mkdir -p "$INSTALL_DIR"
if [ -n "${PANDA_TARBALL:-}" ]; then
  tar xzf "$PANDA_TARBALL" -C "$INSTALL_DIR"
else
  curl -fsSL "$URL" | tar xz -C "$INSTALL_DIR"
fi
echo "Watchdog Panda installed in $INSTALL_DIR"
echo "Run it with: cd \"$INSTALL_DIR\" && TARGET_PROCESS=my-app START_COMMAND=\"nohup ./my-app.sh &\" bash Watchdog.sh"

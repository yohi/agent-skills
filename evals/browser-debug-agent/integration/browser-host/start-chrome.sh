#!/usr/bin/env bash
# Start Chrome on the Browser Host for remote debugging.
# This script is intended to run on the Ubuntu Desktop / Browser Host machine.
# It must NOT be run on the AI Agent Host.

set -euo pipefail

PROFILE_DIR="${HOME}/.local/share/browser-debug-agent/chrome-profile"
CDP_HOST="127.0.0.1"
CDP_PORT="9222"

# Fail closed if Chrome is not installed.
if ! command -v google-chrome >/dev/null 2>&1; then
  echo "ERROR: google-chrome is not installed on this machine." >&2
  echo "Please install Google Chrome on the Browser Host." >&2
  echo "This script will not install Chrome automatically." >&2
  exit 1
fi

# Headful Chrome requires an active graphical session. Do not run this script
# from a plain SSH shell without X11/Wayland forwarding or a desktop session.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "WARNING: neither DISPLAY nor WAYLAND_DISPLAY is set." >&2
  echo "This script is intended to run inside an active Ubuntu Desktop" >&2
  echo "graphical session. Headless mode is intentionally not used, because" >&2
  echo "some UI bugs only reproduce in a real headful browser." >&2
fi

# Ensure the dedicated profile directory exists and is not a personal profile.
if [[ -d "${PROFILE_DIR}" && ! -f "${PROFILE_DIR}/.browser-debug-agent" ]]; then
  echo "WARNING: ${PROFILE_DIR} already exists and may contain data." >&2
  echo "Confirm it is a dedicated automation profile before continuing." >&2
fi

mkdir -p "${PROFILE_DIR}"
touch "${PROFILE_DIR}/.browser-debug-agent"

# Bind only to loopback so the CDP port is not exposed to the LAN/Tailscale.
# Do not use 0.0.0.0 here.
echo "Starting Chrome with remote debugging on ${CDP_HOST}:${CDP_PORT}"
echo "Profile: ${PROFILE_DIR}"

exec google-chrome \
  --remote-debugging-address="${CDP_HOST}" \
  --remote-debugging-port="${CDP_PORT}" \
  --user-data-dir="${PROFILE_DIR}" \
  --no-first-run \
  --no-default-browser-check \
  "$@"

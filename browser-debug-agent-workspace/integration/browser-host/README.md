# Browser Host Setup

## Purpose

This directory contains the script that starts Google Chrome on the **Browser
Host** (Ubuntu Desktop machine) with a dedicated profile and a local-only CDP
endpoint.

## Requirements

- Ubuntu Desktop with `google-chrome` installed.
- An **active graphical session** (X11 or Wayland). This script starts
  **headful** Chrome because some UI bugs only reproduce in a real browser
  window. Do not run it from a plain SSH shell without desktop forwarding.
- `ssh` server reachable from the AI Agent Host.
- A dedicated user account or shell session for automation is recommended.

## Files

- `start-chrome.sh` — Chrome launch script.

## Important notes

- **Graphical session required**: run this script from an active Ubuntu
  Desktop session (terminal inside the desktop, not a plain SSH connection).
  Headless mode is intentionally not used.
- The script binds CDP to `127.0.0.1:9222` **only**. Do not change it to
  `0.0.0.0` or expose the port to LAN/Tailscale directly.
- The script uses a dedicated profile under
  `$HOME/.local/share/browser-debug-agent/chrome-profile`. Never use a
  personal Chrome profile.
- The script **fails closed** if Chrome is not installed. It will not install
  Chrome automatically.

## Usage

On the Browser Host:

```bash
./browser-debug-agent-workspace/integration/browser-host/start-chrome.sh
```

Optional: open a specific URL on start:

```bash
./browser-debug-agent-workspace/integration/browser-host/start-chrome.sh http://127.0.0.1:3000
```

## Verification

After starting Chrome, verify the CDP endpoint is listening on loopback:

```bash
curl -s http://127.0.0.1:9222/json/version
```

You should see a JSON response with Chrome version and protocol information.

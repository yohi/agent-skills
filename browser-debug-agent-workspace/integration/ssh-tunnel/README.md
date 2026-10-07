# SSH Tunnel Setup

## Purpose

This directory contains the script that creates a single SSH connection between
the **Browser Host** (Ubuntu Desktop) and the **Agent Host** (Ubuntu Server).

The tunnel is bidirectional:

```text
Browser Host (where Chrome runs)
  ├─ 127.0.0.1:9222 (Chrome CDP)
  │        ↑
  │   reverse tunnel
  │        ↓
  │  127.0.0.1:9222 on Agent Host
  │
  └─ 127.0.0.1:3000 ( forwarded app )
           ↑
      local forward
           ↓
      127.0.0.1:3000 on Agent Host
```

## Requirements

- SSH access from Browser Host to Agent Host is already configured.
- `GatewayPorts no` is recommended so reverse-tunnel ports bind to loopback
  only on the Agent Host side.
- The Agent Host user can bind `127.0.0.1:9222`.

## Files

- `setup-tunnel.sh` — Starts the SSH tunnel from the Browser Host.

## Important notes

- Both ends of the tunnel bind to **loopback only**. CDP and the web app are
  not exposed to LAN/Tailscale.
- The script is **fail-closed**: `ExitOnForwardFailure=yes` makes the SSH
  process exit immediately if either port forward cannot be established. It
  also uses `ServerAliveInterval=15` / `ServerAliveCountMax=3` so a dead peer
  is detected quickly.
- If the tunnel is down, the browser-debug-agent Skill must report
  `NOT_VERIFIED` or `BLOCKED`. It must not treat a disconnected CDP as success.
- The script does **not** install or configure SSH. Existing SSH credentials
  are required.

## Configuration

Set environment variables before running:

```bash
export AGENT_HOST="agent.example.com"
export AGENT_SSH_USER="agent-user"
export SSH_KEY="$HOME/.ssh/id_ed25519"
```

## Usage

On the Browser Host:

```bash
./browser-debug-agent-workspace/integration/ssh-tunnel/setup-tunnel.sh
```

## Verification

On the **Agent Host**, verify CDP is reachable through the tunnel:

```bash
curl -s http://127.0.0.1:9222/json/version
```

On the **Browser Host**, verify the app is reachable through the tunnel:

```bash
curl -s http://127.0.0.1:3000/api/config
```

## Teardown

Press `Ctrl-C` in the terminal where `setup-tunnel.sh` is running, or kill the
`ssh -N` process.

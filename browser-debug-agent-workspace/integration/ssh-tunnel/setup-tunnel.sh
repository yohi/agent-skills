#!/usr/bin/env bash
# Set up the SSH tunnel between Browser Host and Agent Host.
# This script is intended to run on the Browser Host (Ubuntu Desktop).
#
# It creates a single SSH connection with two tunnels:
#   - Reverse tunnel: Agent Host 127.0.0.1:9222 -> Browser Host 127.0.0.1:9222 (CDP)
#   - Local forward:  Browser Host 127.0.0.1:3000 -> Agent Host 127.0.0.1:3000 (app)

set -euo pipefail

# Configure these via environment variables or edit the defaults.
AGENT_HOST="${AGENT_HOST:-ai-agent}"
AGENT_SSH_USER="${AGENT_SSH_USER:-$(whoami)}"
SSH_KEY="${SSH_KEY:-}"

# Fail closed if either forward cannot be established.
# ExitOnForwardFailure=yes ensures the ssh process exits instead of leaving a
# half-open tunnel. ServerAlive* keeps the connection alive and detects a dead
# peer quickly.
TUNNEL_CMD="ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3"

if [[ -n "${SSH_KEY}" ]]; then
  TUNNEL_CMD="${TUNNEL_CMD} -i ${SSH_KEY}"
fi

TUNNEL_CMD="${TUNNEL_CMD} \
  -R 127.0.0.1:9222:127.0.0.1:9222 \
  -L 127.0.0.1:3000:127.0.0.1:3000 \
  ${AGENT_SSH_USER}@${AGENT_HOST}"

echo "Establishing bidirectional SSH tunnel..."
echo "  - Agent Host can reach Browser CDP at 127.0.0.1:9222"
echo "  - Browser Host can reach Agent app at 127.0.0.1:3000"
echo ""
echo "Command: ${TUNNEL_CMD}"
echo ""
echo "Press Ctrl-C to tear down the tunnel."
echo ""

exec ${TUNNEL_CMD}

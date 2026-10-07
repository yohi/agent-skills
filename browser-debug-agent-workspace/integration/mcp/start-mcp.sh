#!/usr/bin/env bash
# Start the Chrome DevTools MCP server.
# This is a documentation wrapper. The actual MCP server should be configured
# in your MCP client (e.g. Claude Code / OpenCode MCP configuration).
# This script shows the command and runs it in the foreground for testing.

set -euo pipefail

BROWSER_URL="${BROWSER_URL:-http://127.0.0.1:9222}"
MCP_VERSION="${MCP_VERSION:-1.10.1}"

echo "Starting chrome-devtools-mcp@${MCP_VERSION} with browser-url=${BROWSER_URL}"
echo ""
echo "If you run this directly, make sure you have the MCP client configured"
echo "to connect to this server. In most MCP clients the command is:"
echo ""
echo "  npx chrome-devtools-mcp@${MCP_VERSION} --browser-url=${BROWSER_URL}"
echo ""

exec npx "chrome-devtools-mcp@${MCP_VERSION}" --browser-url="${BROWSER_URL}"

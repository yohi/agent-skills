# Chrome DevTools MCP Setup

## Purpose

This directory documents how to connect the official `chrome-devtools-mcp`
package to the real Chrome instance on the Browser Host.

## Important policy

- Use the **official** `chrome-devtools-mcp` package directly. Do not wrap it.
- v1 integration evaluation uses **only** Chrome DevTools MCP. Playwright MCP is
  not required at this stage.
- The MCP connects to `http://127.0.0.1:9222` on the Agent Host, which is
  forwarded through the SSH tunnel to the Browser Host.

## Recommended MCP client command

The integration harness pins the Chrome DevTools MCP version for
reproducibility. Update the pin only after re-verifying the integration.

```bash
npx chrome-devtools-mcp@1.10.1 --browser-url=http://127.0.0.1:9222
```

## Files

- `start-mcp.sh` — A foreground test wrapper. Useful for verifying that the
  MCP can start and connect. In production, configure the command in your MCP
  client instead.

## Verification

1. Start Chrome on the Browser Host.
2. Start the SSH tunnel from the Browser Host.
3. Run `start-mcp.sh` on the Agent Host (or configure the same command in your
   MCP client).
4. Check that the MCP can list pages and that a basic tool call succeeds:

```bash
# CDP reachability
curl -s http://127.0.0.1:9222/json/version

# MCP tool call example (via your MCP client; exact tool name depends on the
# pinned MCP version). The agent PRECHECK must confirm at least one successful
# tool call before proceeding.
```

If Chrome is reachable, you should see a JSON array of open pages.

## Fail-closed behavior

If the SSH tunnel is down or Chrome is not reachable, the MCP will fail to
connect. The browser-debug-agent Skill must detect this during PRECHECK and
report `NOT_VERIFIED` or `BLOCKED`. It must not fabricate a successful browser
verification.

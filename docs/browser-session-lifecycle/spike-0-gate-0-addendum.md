# Spike 0 Gate 0 Addendum — Run 003 authorization gap

Status: DESIGN REVISION PENDING INDEPENDENT REVIEW; NOT PRODUCTION IMPLEMENTATION
Date: 2026-10-11 (JST)

This addendum **does not rewrite** the immutable initial Spike 0 plan
or the frozen Requirements/Design blobs used in Run 001–003.
Those runs and their evidence remain attributed to their original hashes.

## Evidence and scope

Source: Run `spike-0-20261011-003` PR comment
https://github.com/yohi/agent-skills/pull/30#issuecomment-6105066097

The author reports on installed OpenCode 1.18.35:
- MCP tools are available within `session.prompt`, despite absence from
  headless `tool.list()`/`tool.ids()` catalogs.
- `tool.execute.before` rejects Session B and A's child C before fake
  MCP `tools/call`; A's requests reach the same fake MCP.
- **When the Plugin is omitted from config, MCP calls reach the server
  without any authorization check.** This proves OpenCode alone is not
  fail-closed on missing Plugin.
- Alias, plugin config bypass, and release/dispatch races remain to be
  fully proven. No independent review of the local evidence files has
  occurred yet.

## FDR-030-015 — Design amendment

Requirements BSL-034 and Design §5.1.1 require an independent trusted
OpenCode runtime bootstrap/MCP/CDP data-plane gate which stays closed
when the authorization Plugin is not loaded/attested, and which
revokes accepted streams if that authority is lost.

The exact choice between Supervisor-gated MCP publication/transport
and genuinely isolated per-session MCP routing must be selected from
evidence, not asserted to exist.

## Next gated work

- **Gate 0 (read-only/disposable test only):** inspect installed OpenCode
  config resolution/loading/restart semantics; implement a throwaway
  `supervisor absent-plugin -> Broker refuses CDP` probe, if it can be
  exercised without privileged host mutation. Test absent plugin, load
  exception, malicious project override, startup race, Plugin shutdown
  and session A/B calls. Record *both* model/MCP `tools/call` traces and
  Broker denied data-stream traces. Do not claim a mock verifies
  real-host lifecycle.
- **Independent Design Review:** audit BSL-034 and Design §5.1.1 for
  non-bypassable config/transport control and recovery semantics.
- **Gate H:** remains blocked until the human approves exact host/user/
  sshd/systemd/namespace/GUI change requests. No implicit approval.
- **SP0-02 onward:** run against a separately approved and frozen
  revised baseline only after Design review, preserving Run 001–003
  evidence as historical with their original SHA references.

No extension of Gate H or production implementation authorization is
granted by this document.

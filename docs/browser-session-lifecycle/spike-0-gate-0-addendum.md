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

## FDR-030-016–019 — Mandatory BSL-034 closure matrix

Original `spike-0-verification-plan.md` remains immutable for Run 001–003.
This addendum **extends** SP0-01, SP0-03, SP0-05, SP0-06, SP0-08, SP0-09
and SP0-11 for new runs; an agent MUST use both matrices and the approved
new Requirements/Design blob hashes. A pass of BSL-031 **alone** is not
a pass of BSL-034.

Record each case with `run_id`, `case_id`, `FDR/BSL mapping`, frozen
review HEAD/blobs, exact Runtime/MCP/owner/lease/connection-generation
identity, expected vs observed Broker Guard state, local/remote
CDP byte-admission and MCP `tools/call` counters, auth principal,
timestamps/linearization points, command ID/exit code, test environment
(`mock` / `isolated-process` / `two-host-real`), redacted log filenames
and sha256, cleanup state, verdict and blocking reason. For each test
include **both** MCP trace and trusted Agent/Desktop Broker trace; if one
is unavailable, explain and mark the security claim `NOT_PROVEN`.

| Case ID | Contract / Spike tasks | Mandatory negative control and passing observation |
| --- | --- | --- |
| G034-01 | BSL-034/035, FDR-030-015/016; SP0-01/08 | Plugin omitted/missing config: bare OpenCode may call fake MCP, but protected Broker CDP route stays DENY; no READY |
| G034-02 | BSL-034/035; SP0-01/08 | Plugin import exception/partial initialization cannot enable protected MCP CDP or leave partial authority |
| G034-03 | BSL-035, FDR-030-016; SP0-03/08 | Alter project config/Plugin order/registration; protected runtime fails startup or ignores untrusted overrides; broker denies |
| G034-04 | BSL-034/037, FDR-030-018; SP0-01/08 | MCP publishes before guard verification; no CDP bytes until verified ACTIVE |
| G034-05 | BSL-035, FDR-030-016; SP0-03/06 | Pluginless separate OpenCode Runtime, forged Supervisor IPC, inherited FDs, namespace/UDS access all denied |
| G034-06 | BSL-036, FDR-030-017; SP0-01/08 | Old Runtime incarnation/MCP identity or owner-session proof replay rejected |
| G034-07 | BSL-036, FDR-030-017; SP0-05/08 | Old lease epoch/SSH connection generation proof replay on reconnect rejected |
| G034-08 | BSL-036, FDR-030-017; SP0-08/09 | Agent Broker restart returns DENY; no persisted ACTIVE proof reuse or stale stream |
| G034-09 | BSL-037, FDR-030-018; SP0-08/09 | Planned Guard reload/disable publishes FENCING and drops OPEN/DATA/accepted WS **before** guard can disappear |
| G034-10 | BSL-037, FDR-030-018; SP0-05/09 | Runtime crash leaves no MCP/orphan WS/CDP stream able to send after guard invalidation, even with delayed notification |
| G034-11 | BSL-037, FDR-030-018; SP0-05/09 | Supervisor/Agent Broker failure and stale Desktop SSH stream cannot continue CDP access during recovery |
| G034-12 | BSL-031/034/035/036/037; SP0-01/08 | Protected live case: same official MCP receives A ALLOW, B and child REJECT before dispatch; session/MCP/epoch/generation bound |
| G034-13 | BSL-037, FDR-030-018; SP0-05/09 | In-flight WebSocket/DATA vs Guard FENCING vs SSH N→N+1 race: no post-fence frames admitted |
| G034-14 | BSL-035/036/037; SP0-08/09 | Guard crash, Supervisor restart and new Runtime require new authenticated proof and close old streams; no false VERIFIED |

**Evidence closure:**
- Each G034-01..14 is **mandatory**, with case-level status
  `PROVEN / NOT_PROVEN / BLOCKED / NOT_RUN / INDETERMINATE`.
  `NOT_APPLICABLE` is allowed only where an impossible runtime transition
  is actually proven by installed-source/OS facts **and** an equivalent
  positive guard lifetime + negative access test covers the same threat;
  the independent reviewer must approve the substitution.
- A fake MCP/isolated relay may prove hook mechanics, not cross-UID
  or two-host security. G034-05, -07, -08, -10, -11 and -13 require real
  privileges/OS lifetimes and, where relevant, both hosts in Gate H.
  Mock-only verdicts never close real-host obligations.
- SP0-11 MUST include FDR-030-015–019, BSL-034–037 and all case IDs in
  `cases.jsonl`, manifest and per-contract evidence/cleanup ledger.
  `SPIKE_PROVEN` is forbidden if any mandatory case is NOT_PROVEN,
  BLOCKED, NOT_RUN, INDETERMINATE, unapproved NA, lacks a Broker/MCP
  trace, or if temporary test resources were not safely cleaned up.
  Any partial Run remains `SPIKE_INCOMPLETE`; do not promote BSL-031
  success into global SP0-01 or Spike PASS.
- Amend this supplemental matrix only in a separately reviewed Design/
  Spike plan baseline. Run 001–003 evidence retains original SHAs.

## Next gated work

- **Gate 0 (read-only/disposable test only):** inspect installed OpenCode
  config resolution/loading/restart semantics and Supervisor IPC policy;
  implement a throwaway `supervisor absent-plugin -> Broker refuses CDP`
  proof and replay/byte-fencing probes, if possible without privileged
  host mutation. Test G034-01..04 and 06/09/12 locally, marking any
  incomplete OS/host claim NOT_PROVEN; leave all Gate H tests blocked.
  Record *both* MCP `tools/call` and Broker stream traces.
- **Independent Design Review:** audit BSL-034–037 and Design
  §2/§5.1.1–5.1.3 for protected Supervisor principal, proof authenticity,
  zero-window fencing and this complete G034 closure matrix.
- **Gate H:** remains blocked until the human approves exact host/user/
  sshd/systemd/namespace/GUI change requests. No implicit approval.
- **SP0-02 onward:** run against a separately approved and frozen
  revised baseline only after Design review, preserving Run 001–003
  evidence as historical with their original SHA references.

No extension of Gate H or production implementation authorization is
granted by this document.

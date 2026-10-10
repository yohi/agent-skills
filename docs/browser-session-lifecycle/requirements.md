# Browser Session Lifecycle Integration — Requirements

Status: DRAFT — for independent design review, not implementation authorization
Date: 2026-10-10 (JST)
Target: `yohi/agent-skills`; `browser-debug-agent` Skill + OpenCode v1 adapter

## 1. Purpose and user experience

A user on the Agent Host (Ubuntu Server) starts an AI agent and asks it to
inspect or fix a web UI. Without first touching the Browser Host (Ubuntu
Desktop), the agent obtains a dedicated headful Chrome session on that Desktop
over the existing private Tailscale network, uses the official Chrome DevTools
MCP, and relinquishes *only its own resources* when the browser task or owning
agent session ends. Crashes and network partitions must also result in eventual
cleanup and an explicit failed-verification result.

The Skill remains the **user-visible entry point and workflow authority**. A
separate Browser Session Controller owns lifecycle and connectivity; the Skill
does **not** implement CDP, Chrome process control, or the SSH transport.

## 2. Current baseline and compatibility

- Existing Skill: `skills/browser-debug-agent/SKILL.md`.
- Existing v1 evaluation harness: `evals/browser-debug-agent/integration/`.
- Historical integration results A/B `FIX_VERIFIED`, C `NOT_VERIFIED`
  (correct fail-closed), on a manually started Desktop Chrome and Desktop-to-
  Agent SSH reverse tunnel.
- Current harness uses `start-chrome.sh`, `setup-tunnel.sh` and
  `chrome-devtools-mcp@1.10.1 --browser-url=http://127.0.0.1:9222`.
- PR #29 concerns reproducible integration fixtures and is independent of this
  proposal. Do not build lifecycle behavior into those fixtures.
- The existing PRECHECK/BASELINE/REPRODUCE/OBSERVE/DIAGNOSE/FIX/VERIFY/REPORT
  semantics, explicit FIX authorization, and fail-closed guarantees survive.

## 3. Functional requirements

| ID | Requirement | Acceptance evidence |
| --- | --- | --- |
| BSL-001 | Explicit browser-related prompts activate the existing Skill; non-browser work does not start Chrome. | Invocation and negative activation tests |
| BSL-002 | Skill can call `browser_session.acquire`, `status`, `release` exposed through an OpenCode integration. | Real OpenCode tool calls |
| BSL-003 | Agent Host initiates SSH to Browser Host via Tailscale without Browser Host initiating a tunnel. | Real 2-host connection traces |
| BSL-004 | Browser Host starts **headful** Chrome in the active, authorized graphical login session, using an isolated automation-only profile. | Browser display/session and profile identity |
| BSL-005 | The Agent-local `127.0.0.1:9222` exists only inside the authorized MCP isolation domain. SSH forwards to a *lease-unique, non-reused* Desktop Unix socket relay, never a shared Desktop CDP TCP port. | Namespace inspection, socket identity, stale-tunnel denial |
| BSL-006 | When the test application runs on Agent Host, provide an optional Browser-Host-local reverse forward to the Agent app loopback endpoint; do not create it otherwise. | Host sees expected app and forwarding absence when unnecessary |
| BSL-007 | READY requires owned SSH, intended isolated Chrome, and `list_pages` from the **exact OpenCode-managed MCP instance exposed to the Skill**, bound to the current lease epoch. | Same-instance MCP call and epoch identity trace |
| BSL-008 | Repeated acquire by the same owner is idempotent and does not spawn another Chrome/tunnel. | Duplicate calls, same lease |
| BSL-009 | v1 permits one exclusive browser owner per Browser Host; another session gets `BROWSER_SESSION_BUSY` without stealing it. | Concurrent acquisition test |
| BSL-010 | A release stops **only** the authenticated lease's tunnel and Chrome; no `pkill ssh`, broad service stop, or manipulation of personal Chrome. | Process/unit ownership assertions |
| BSL-011 | Adapter persists the result and attempts release **before emitting the final report**; `session.deleted` releases, `session.idle` starts bounded grace. LLM prose `finally` is not an execution guarantee. | Ordered event traces, skipped-release fallback |
| BSL-012 | Agent crash, tunnel loss, forgotten release or Desktop manager failure must revoke Desktop CDP ingress and accepted streams, then reap only owned Chrome without an Agent callback. | Kill -9, tunnel-only failure, timeout and manager restart tests |
| BSL-013 | Agent/Desktop restarts reconcile durable lease epochs/tombstones; revoked generations cannot be reactivated or adopted, even if an old SSH process remains. | Crash/restart replay and fencing tests |
| BSL-014 | Chrome unavailability, GUI not logged in, session lock/no access, target app unavailable, port occupied, SSH failure and MCP failure yield typed errors and browser `NOT_VERIFIED`/`BLOCKED`. | Negative scenarios; no browser fallback |
| BSL-015 | Caller can inspect lease status without reading personal browser state. | `status` contract assertions |
| BSL-016 | Explicit release is idempotent and reports partial cleanup as `CLEANUP_PENDING` until confirmed. | Repeated release, failures |
| BSL-017 | A browser-verified outcome requires the original Skill evidence and same-scenario browser recheck; successful acquisition alone never means `VERIFIED`. | A/B/C regression evidence |
| BSL-018 | OpenCode adapter may change independently of the OS-neutral controller. | Mock adapter and controller tests |

## 4. Security / reliability constraints

| ID | Constraint |
| --- | --- |
| BSL-S01 | One pre-provisioned dedicated non-admin GUI account owns the graphical login, restricted SSH principal, Chrome user service, host relay, lease store and watchdog. No general SSH shell, agent/X11 forwarding or personal Chrome use. A narrowly provisioned privileged namespace bootstrap is permissible only when technically required and must never execute arbitrary model-provided commands. |
| BSL-S02 | Loopback binding is not authorization. Desktop Chrome CDP TCP must reside inside a lease-specific network namespace; a revocable, lease-specific Unix socket relay is the only ingress for SSH. Agent CDP TCP and official MCP must run in an isolated namespace/security domain inaccessible to ordinary Agent/test processes. If isolation cannot be proven, fail closed. |
| BSL-S03 | Desktop management command supports only allowlisted `start/status/renew/release` operations, typed inputs, and bounded resources; arbitrary shell commands are outside the interface. |
| BSL-S04 | Controller generates unguessable lease credentials outside LLM context; owner/session IDs alone are not sufficient to stop resources. Redact keys/tokens, cookies and URLs containing secrets. |
| BSL-S05 | Independent Desktop watchdog must revoke ingress, expire leases and durably replay cleanup. The dedicated systemd user manager must survive GUI logout via linger or a proven equivalent; logged-out mode is cleanup-only. `trap EXIT` and session callbacks alone are insufficient. |
| BSL-S06 | A port already held by a foreign service, unknown CDP browser, or existing personal Chrome is not reused or terminated. Fail closed. |
| BSL-S07 | Every Chrome profile is session-owned and private (0700). Cleanup may erase only a controller-created, verified owned ephemeral profile; never delete an inherited or personal profile. |
| BSL-S08 | Session IDs and host aliases supplied by the model are not authoritative; the adapter derives ownership from verified OpenCode execution context and server-side lease state. |
| BSL-S09 | Bounded waits/retries and explicit error codes are mandatory. No infinite retry, silent headless substitution, or Playwright fallback to a different browser. |
| BSL-S10 | No controller implementation writes changes to the source project being debugged unless the original Skill's FIX authorization permits it. |

## 5. Defined lifecycle and outcome semantics

- `UNALLOCATED → STARTING → READY → IDLE → RELEASING → CLOSED`.
- Any startup failure ends `BLOCKED` and performs compensating cleanup; cleanup
  failures remain `CLEANUP_PENDING`, with the watchdog as the final backstop.
- `session.idle` is *not* a definitive session-end signal.
- A trusted adapter/supervisor captures evidence, durably finalizes the browser
  outcome, attempts release with bounded waiting, and only then emits the final
  report. Cleanup failures are separately marked `CLEANUP_PENDING`. The host
  watchdog remains the last-resort recovery authority.
- `READY` means transport + intended browser + actual MCP health, not that
  any app behavior or bug fix was verified.
- The existing `FIX_VERIFIED`, `FIX_APPLIED_NOT_VERIFIED`,
  `NOT_VERIFIED`, `BLOCKED` and `ROOT_CAUSE_NOT_PROVEN` remain unchanged.

## 6. Explicit non-goals (initial rollout)

- Booting an asleep Desktop (Wake-on-LAN), automatically logging into GNOME,
  unlocking a locked session, remote desktop/VNC, headless fallback.
- More than one active browser owner on the same Desktop.
- Managing, borrowing or deleting a user's ordinary Chrome profile.
- Replacing the official Chrome DevTools MCP with custom browser control.
- Supporting every AI agent runtime simultaneously: implement OpenCode v1
  first, with an adapter boundary for future clients.

## 7. Acceptance gates

1. **Contract spike**: Verify exact OpenCode v1 plugin/custom-tool/event shapes,
   ordering and process exit behavior against installed version; verify
   `systemd --user` can launch Chrome in the actual GUI session and the SSH
   direction works. Unverified API assumptions block implementation.
2. **Unit**: Epoch fencing, access revocation, idempotency, timeout-gated
   renewal, state transitions, port conflicts, rollback and typed failures.
3. **Two-host**: Autonomous START → isolated tunnel/CDP → `list_pages` using
   the exact owning OpenCode MCP → RELEASE. Verify negative CDP access from
   unauthorized processes on **both hosts**.
4. **Recovery**: Kill -9, tunnel-only loss while management SSH remains live,
   stale Tunnel A versus successor Chrome B, epoch races, Desktop logout,
   user-manager crash/restart, watchdog replay and independent expiry.
5. **Skill regression**: Existing Scenario A/B outcomes stay evidence-based;
   Scenario C stays fail-closed. Newly automated bootstrap failures do not get
   misreported as source defects.
6. **Security**: Isolated CDP on both hosts, no stale forwarding access to
   successor Chrome, no arbitrary SSH command/personal profile use, and no
   secret-bearing reports.

## 8. Decisions requiring evidence before final approval

- The installed OpenCode version/hook payloads, whether direct MCP tool calls
  can be gated, and whether MCP initialization tolerates an initially missing
  CDP endpoint.
- The dedicated GUI UID, GNOME user service environment, isolated Chrome
  network egress and access to the intended graphical session.
- Restricted SSH commands, lease-specific Unix socket forwarding, Agent MCP
  confinement, Desktop user-manager lingering, and cleanup-on-restart.
- Timeout/heartbeat/idle grace defaults after two-host measurements.

No production implementation is authorized by this draft.

## 9. Normative remediation contracts — FDR-030-001 through 007

### BSL-019 — Lease-scoped revocation and generation fencing (001)

Each Desktop lease owns a never-reused random epoch and a uniquely named
Unix-domain socket under an owner-controlled private path. SSH `-L` targets
that exact remote socket; it must never target a recyclable Desktop
`127.0.0.1:9222` listener. On expiry or release Desktop authority atomically
marks the epoch REVOKED and rejects new relay connections, closes all
active and pending relay streams, closes/unlinks the socket, and stops Chrome.
Re-acquisition B cannot begin until A's ingress-revocation barrier finishes.
Retired paths/generations must never be recreated, including after reboot.

Test: keep SSH Tunnel A alive after A expires, acquire B, and prove A's
existing WebSockets *and* fresh requests cannot reach Chrome B. Simulate
expiration/acquire races and restarts; expired credentials never revive.

### BSL-020 — Same-host CDP security on both endpoints (002)

Threat model explicitly distrusts ordinary application/test processes,
other OpenCode sessions and unrelated local processes, even on the same
machine. Sharing a user login or loopback interface alone does not authorize
CDP. Trusted components: kernel/host admin and a narrowly pre-provisioned,
privilege-separated controller; compromise of root/kernel or theft of the
controller's restricted SSH key is out of scope.

Desktop's Chrome+CDP TCP live in a lease-specific isolated network namespace.
A revocable Unix socket relay inside that domain is reachable by the restricted
SSH endpoint only. Isolate Agent's SSH local-forward listener and the *same
official MCP instance* in a separate local network/credential domain: ordinary
agent shell/test processes must not connect to that TCP listener. Establish
a tested Internet and optional Agent-local application route for Chrome; mere
`PrivateNetwork=yes` with loopback-only networking is insufficient to browse
a real website. A limited pre-provisioned privileged setup component is
allowed for namespace/veth/NAT only; it cannot accept arbitrary commands.

Test: with an active lease, unauthorized Agent and Desktop processes cannot
connect to either CDP TCP or the Unix socket, but the owning MCP can. Test
same-login untrusted Agent subprocesses, WebSocket upgrade, and route isolation.
Fail BLOCKED rather than downgrading to loopback-only.

### BSL-021 — Heartbeat health gates and bounded reconnect (003)

Renewal requires: current unrevoked epoch, rightful OpenCode owner active
or inside allowed idle grace, owned tunnel process identity alive, real CDP
connectivity through **its own** lease socket, and a bounded health call
from the exact MCP instance. Successful management SSH by itself is
insufficient. When tunnel health fails, immediately suspend renewals and
declare DEGRADED; bounded reconnect is allowed only to the same unrevoked
epoch, without shifting to another endpoint. A fixed, non-extendable recovery
deadline must expire even if management SSH and the OpenCode session remain
healthy. Reconnection to a revoked epoch is forbidden.

Test: stop only the data tunnel while management SSH and OpenCode stay alive;
Chrome must be revoked and stopped within the loss deadline plus watchdog
interval, and the Skill cannot claim verified browser results.

### BSL-022 — Dedicated GUI user / principal relationship (004)

A pre-provisioned dedicated non-admin GUI user (symbolic name `browser-agent`)
owns the Desktop login, systemd user manager, Chrome service, relay, lease
database and reaper. Restricted SSH keys authenticate as *that same UID*,
with a forced allowlisted command for management and separately constrained
forwarding authorization. The restricted account must not be shared with
test workloads or a personal Chrome profile. The Chrome process is additionally
isolated from the relay socket in its mount/access domain. A different GUI
UID vs SSH UID is not implicitly supported; it requires a separately reviewed,
authenticated cross-UID broker.

Test: actual Desktop UID/seat, SSH command UID, Chrome UID, namespace and
reaper UID match the declared boundaries, without running Chrome as root.

### BSL-023 — Watchdog lifetime and GUI logout (005)

Pre-provision `loginctl enable-linger` or prove an equivalent cleanup supervisor;
lingering preserves the user manager, **not** a graphical login. On GUI logout
or loss of the intended seat, deny acquisitions and revoke existing sessions.
Use private durable REVOKING/CLEANUP_PENDING tombstones and a reaper that
reconciles them after user-manager restart/reboot. No successor lease is
allowed until prior ingress was disabled and owned processes were confirmed
stopped. If user-manager shutdown leaves processes running, an independently
effective fail-closed shutdown mechanism is required and must be proven.

Test: logout, re-login, stop/start the user manager, reboot/reaper restart;
the old CDP is not usable and incomplete cleanup resumes safely.

### BSL-024 — Finalize, release, then emit (006)

A trusted adapter/supervisor, not a natural-language Skill instruction,
enforces `CAPTURE_EVIDENCE → FINALIZE_RESULT → RELEASE → EMIT_REPORT`.
Commit the evidence/result before cleanup; bound release wait and persist
cleanup intent. When release fails, report both the unchanged evidence-based
browser result and `CLEANUP_PENDING`. Plugin event listeners and the Desktop
watchdog recover if the model or adapter does not finish.

Test: normal completion, response cancellation, tool error, process kill and
release failure; never rely on a tool invocation after the final reply.

### BSL-025 — Same MCP instance and lifecycle gating (007)

READY requires `list_pages` through the exact OpenCode-registered official
Chrome DevTools MCP instance later used by the owning Skill, not a second
process spawned just for diagnostics. Bind MCP process/session identity to
the lease epoch and revoke its CDP access when that epoch ends. Reject
unguarded direct browser MCP calls before acquire or after release.
The installed OpenCode version's hooks, stdio registration, initialization
order and client routing must be demonstrated by a contract spike.

Test: a separate test MCP succeeds while the Skill-registered MCP is broken;
READY must fail. Compare instance/epoch identity for probe and actual calls.

### BSL-026 — Implementation authorization gate

All seven corrections must pass independent Design Review and the real
two-host contract spike before implementation is authorized. Inability to
prove the host GUI/namespace/egress model, localhost CDP isolation,
SSH socket forwarding permissions, OpenCode gating/instance identity, or
manager cleanup is DESIGN_BLOCKED, not a reason to reduce security requirements.

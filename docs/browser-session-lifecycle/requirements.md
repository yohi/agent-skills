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
| BSL-005 | Agent-local CDP endpoint binds `127.0.0.1:9222` and forwards only to the intended Browser Host `127.0.0.1:9222`. | Both listeners + CDP owner check |
| BSL-006 | When the test application runs on Agent Host, provide an optional Browser-Host-local reverse forward to the Agent app loopback endpoint; do not create it otherwise. | Host sees expected app and forwarding absence when unnecessary |
| BSL-007 | Connection is READY only after SSH, intended host-owned Chrome, CDP product/version, and a genuine DevTools MCP tool call succeed. | `/json/version` and MCP `list_pages` results |
| BSL-008 | Repeated acquire by the same owner is idempotent and does not spawn another Chrome/tunnel. | Duplicate calls, same lease |
| BSL-009 | v1 permits one exclusive browser owner per Browser Host; another session gets `BROWSER_SESSION_BUSY` without stealing it. | Concurrent acquisition test |
| BSL-010 | A release stops **only** the authenticated lease's tunnel and Chrome; no `pkill ssh`, broad service stop, or manipulation of personal Chrome. | Process/unit ownership assertions |
| BSL-011 | On Skill completion, release its lease; on session deletion, release; on `session.idle`, apply a bounded grace policy, not an immediate assumption of session termination. | Hook/lease transition tests |
| BSL-012 | On agent crash, forced kill, tunnel loss or forgotten release, Browser Host expires the lease and removes host-owned Chrome without requiring an agent callback. | Kill -9 / partition and reaper tests |
| BSL-013 | Agent/controller restarts reconcile from durable identity and ownership, never adopt an unowned Chrome or tunnel. | Crash/restart replay tests |
| BSL-014 | Chrome unavailability, GUI not logged in, session lock/no access, target app unavailable, port occupied, SSH failure and MCP failure yield typed errors and browser `NOT_VERIFIED`/`BLOCKED`. | Negative scenarios; no browser fallback |
| BSL-015 | Caller can inspect lease status without reading personal browser state. | `status` contract assertions |
| BSL-016 | Explicit release is idempotent and reports partial cleanup as `CLEANUP_PENDING` until confirmed. | Repeated release, failures |
| BSL-017 | A browser-verified outcome requires the original Skill evidence and same-scenario browser recheck; successful acquisition alone never means `VERIFIED`. | A/B/C regression evidence |
| BSL-018 | OpenCode adapter may change independently of the OS-neutral controller. | Mock adapter and controller tests |

## 4. Security / reliability constraints

| ID | Constraint |
| --- | --- |
| BSL-S01 | SSH authentication is non-interactive, key-scoped and tied to a pre-provisioned, non-admin Desktop account. No sudo/root, agent forwarding, X11 forwarding or personal desktop session access. |
| BSL-S02 | CDP and reverse-forward listening sockets bind to loopback. The only remotely reachable service is the already-authorized SSH path over Tailscale. |
| BSL-S03 | Desktop management command supports only allowlisted `start/status/renew/release` operations, typed inputs, and bounded resources; arbitrary shell commands are outside the interface. |
| BSL-S04 | Controller generates unguessable lease credentials outside LLM context; owner/session IDs alone are not sufficient to stop resources. Redact keys/tokens, cookies and URLs containing secrets. |
| BSL-S05 | A host watchdog independently enforces an expiring lease; `trap EXIT` or `session.deleted` alone is insufficient. |
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
- Normal Skill REPORT calls `release` in a finally/finalization path after
  evidence has been secured. Adapter-level lifecycle handling is a secondary
  guarantee, and host watchdog is the final recovery mechanism.
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
2. **Unit**: State machine, idempotency, lease authorization, expiry,
   conflict/port collisions, rollback and typed failures.
3. **Two-host**: Autonomous START → tunnel → CDP → real MCP `list_pages` →
   RELEASE; only owned Chrome/SSH are stopped.
4. **Recovery**: Real forced agent kill, offline Desktop, SSH loss, OpenCode
   idle/delete and independent lease expiry; no residual live CDP after TTL.
5. **Skill regression**: Existing Scenario A/B outcomes stay evidence-based;
   Scenario C stays fail-closed. Newly automated bootstrap failures do not get
   misreported as source defects.
6. **Security**: No non-loopback CDP, no arbitrary SSH command, no personal
   profile use, no secret-bearing reports.

## 8. Decisions requiring evidence before final approval

- The installed OpenCode version/hook payloads, whether direct MCP tool calls
  can be gated, and whether MCP initialization tolerates an initially missing
  CDP endpoint.
- GNOME Wayland/X11 user service environment and appropriate graphical session
  lifetime on the real Browser Host.
- Safe SSH command restrictions and launch/forwarding credentials on the
  actual Tailscale/Ubuntu installation.
- Timeout/heartbeat/idle grace defaults after two-host measurements.

No production implementation is authorized by this draft.

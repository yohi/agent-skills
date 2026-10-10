# Browser Session Lifecycle Integration — Technical Design

Status: DRAFT — subject to contract spike and independent review
Date: 2026-10-10 (JST)
Requirements: [requirements.md](requirements.md)

## 1. Decision

**Single user entry point, separate ownership boundaries:**

```text
OpenCode (Agent Host, Ubuntu Server)
  └─ browser-debug-agent Skill (workflow authority)
       └─ browser_session tool (OpenCode adapter)
            └─ Agent Controller (lease/state/SSH ownership)
                 ├─ SSH remote control: start/status/renew/release
                 ├─ SSH -L 127.0.0.1:9222 → Desktop 127.0.0.1:9222
                 ├─ optional SSH -R Desktop 127.0.0.1:3000 → Agent 127.0.0.1:3000
                 └─ Chrome DevTools MCP (official, pinned)
                      ↓
Browser Host (Ubuntu Desktop)
  ├─ sshd (existing Tailscale-restricted access)
  ├─ browser-sessionctl (restricted control verbs)
  ├─ systemd --user (transient owned Chrome service)
  ├─ systemd --user timer/service (lease expiry reaper)
  └─ headful Chrome (owned temporary automation profile, loopback CDP)
```

Keep `browser-debug-agent`'s browser debugging workflow and terminal states.
The Skill calls `browser_session.acquire` before its existing PRECHECK and
`browser_session.release` after REPORT. A failed acquire is an explicit
`NOT_VERIFIED`/`BLOCKED` and still records NOT_COLLECTED observation fields.

**No custom CDP wrapper**. The Session Controller does not inspect pages or
forge browser evidence. The official MCP remains the only browser tool.

## 2. Trust boundaries and ownership

1. The OpenCode adapter extracts the verified session ID and agent process
   context from the runtime; the LLM may request acquire/release but cannot
   nominate an arbitrary owner or host shell command.
2. The Agent Controller issues a cryptographically random lease ID/token, stores
   it under an owner-only runtime directory (0700), and never emits the token
   into tool results, transcript or logs.
3. The Desktop Controller authenticates a restricted SSH principal and validates
   a lease-specific capability for `renew/release`. Ownership is checked
   against its state under a locked private directory.
4. All Chrome, profile, tunnel and service artifacts are tagged with lease
   identity; the controller never adopts or terminates foreign instances.
5. Exclusive v1 lock guards the fixed CDP endpoint and Desktop Chrome.
   Different owners receive `BROWSER_SESSION_BUSY`; same owner receives
   the existing lease if still healthy.
6. The environment must not require a root service or an arbitrary remote shell
   for normal operation. One-time human provisioning of SSH key restrictions and
   `systemd --user` timer is allowed.

## 3. Interface contract (logical schema)

These are **design contracts**, not claims that the current plugin already
provides these methods.

```text
browser_session.acquire(target_url?, app_forward?)
  ownership: injected by adapter, not LLM
  return: {state: READY, lease_handle: opaque, cdp_url: "http://127.0.0.1:9222",
           chrome_product, chrome_version, mcp_ready: true}
  error:  {state: BLOCKED | NOT_VERIFIED, code, stage, cleanup_state}

browser_session.status()
  return: {state, code?, lease_healthy, cdp_healthy, cleanup_state}

browser_session.release()
  return: {state: CLOSED | CLEANUP_PENDING, cleanup_state, code?}
```

The handles returned to the model are non-sensitive labels, not bearer tokens.
Host-controller wire commands use authenticated, typed requests and supply
private credential material through a protected channel (not argv/log output).
All APIs are bounded, idempotent and reject unknown fields and invalid IDs.

Error codes include:
`GUI_SESSION_UNAVAILABLE`, `DESKTOP_UNREACHABLE`, `SSH_AUTH_FAILED`,
`CHROME_START_FAILED`, `CDP_PORT_OCCUPIED`, `CDP_UNAVAILABLE`,
`MCP_UNAVAILABLE`, `APP_FORWARD_UNAVAILABLE`, `BROWSER_SESSION_BUSY`,
`LEASE_LOST`, `CLEANUP_PENDING`, `UNKNOWN_OWNER`.

The contract must document distinction between provisionally connected CDP
and an actual successful MCP tool call. The latter is required for READY.

## 4. Agent Host acquisition sequence

1. Accept Skill/Plugin acquire only for browser work. A per-owner lock
   serializes calls; re-entrant calls use the same healthy lease.
2. Validate configured Desktop identity, key scope, SSH reachability, target
   URL and optional app endpoint. Do not guess URLs.
3. Via *restricted SSH management command*, inspect Desktop GUI readiness and
   check that no foreign Chrome or service owns the requested CDP port.
4. Atomically create lease in STARTING with short provisional expiry. Start
   Chrome as a `systemd --user`-owned service in the pre-existing GUI user's
   graphical environment. Reject ambiguous or absent GUI sessions.
5. Confirm Desktop port `127.0.0.1:9222` belongs to the **owned** Chrome unit,
   and Desktop `/json/version` returns expected Chrome identity.
6. Agent starts its own tracked SSH tunnel process, with loopback-only
   `-L 127.0.0.1:9222:127.0.0.1:9222` and, *only for Agent-local apps*,
   `-R 127.0.0.1:3000:127.0.0.1:3000` (or explicitly configured port).
   Use `BatchMode=yes`, `ExitOnForwardFailure=yes`, server-alive settings,
   no X11/agent forwarding, and explicit SSH identity. The tunnel process
   identity is stored by the Agent Controller; never use `pkill ssh`.
7. Assert local port ownership and CDP response through the new forward, then
   issue a genuine Chrome DevTools MCP `list_pages` call. Mere `npx` startup
   or `curl` does not establish MCP readiness.
8. Commit state READY only after all checks. If any step fails, stop the owned
   tunnel/unit and revoke the provisional lease. If cleanup is incomplete,
   report `CLEANUP_PENDING` for watchdog recovery.

Use a fixed Agent-local port 9222 and one owner for v1. Any conflicting
listener is a hard error. Optional app `-R` likewise fails on port collision;
never expose `0.0.0.0`. A port bind being accepted does *not* by itself prove
the ultimate target service is reachable.

## 5. Desktop user session and process supervision

Use an existing logged-in Ubuntu Desktop graphical user session. SSH login
environment (`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, DBus address)
is **not** assumed to be the GUI environment. One-time setup must ensure the
relevant environment is safely registered with the systemd user manager from
the actual Desktop session; verify that launching a transient user service
opens Chrome in the intended seat.

Create an explicitly session-owned unit/profile with restrictive permissions.
Do not start Chrome under root, borrow a personal Chrome process, turn on
headless mode silently, or delete an unknown profile. Profile destruction is
permitted only for verified controller-created ephemeral paths after stopping
the owning Chrome; otherwise report cleanup pending.

No assumption is made that the GUI is available while logged out, locked,
asleep, or during a display-manager transition. Non-ready GUI is BLOCKED.
Supporting WoL/unlock/autologin is outside the first rollout.

## 6. Lease, heartbeat and cleanup

```text
UNALLOCATED --acquire--> STARTING --validated--> READY
    READY --no active work--> IDLE --reuse--> READY
    READY/IDLE --release/delete/expiry--> RELEASING --> CLOSED
    STARTING --failure--> RELEASING --> CLOSED or CLEANUP_PENDING
    READY/IDLE --lost tunnel/host--> NOT_VERIFIED + cleanup pending
```

**Two independent recovery paths**:

- Agent-side adapter attempts release on Skill finalization, on observed
  `session.deleted`, and after bounded idle grace. Plugin process-exit
  cleanup is best-effort, never the sole guarantee.
- Desktop-side `systemd --user` timer periodically checks lease expiry
  without contacting Agent Host; after expiry, it stops only the matching
  Chrome user unit and removes owned ephemeral artifacts.

A separate Agent Controller heartbeat renews the Desktop lease while a
legitimately owned active/idle-grace session exists. Heartbeats must not depend
on individual browser tool invocations (the LLM may think for a long time).
Heartbeat loss does not grant continued unlimited access. Suggested starting
values for a spike: 30 s heartbeat, 180 s lease TTL, 60 s reaper interval,
120 s session-idle grace; these are **not yet validated defaults**.

Normal Skill finalization releases promptly, after browser evidence is
captured; `session.idle` merely starts a grace timer. Release attempts are
safe to repeat. If Agent cannot reach Desktop after terminating its own tunnel,
the Desktop lease still expires independently.

The adapter must use a verified event subscription mechanism. OpenCode
`session.idle` must not be mistaken for session termination. The installed
OpenCode hook/event payload schemas and ordering must be tested before code
implementation. If `tool.execute.before` cannot reliably gate direct browser
MCP tools, the design must explicitly prevent unmanaged MCP calls in another
tested way or keep the integration NOT_READY.

## 7. Skill workflow insertion

```text
SKILL ACTIVATION
  → ACQUIRE_BROWSER_SESSION
       ├─ READY → original PRECHECK
       └─ failure → NOT_VERIFIED/BLOCKED + NOT_COLLECTED ledger + REPORT
  → BASELINE
  → REPRODUCE
  → OBSERVE
  → DIAGNOSE
  → FIX (only if authorized)
  → VERIFY
  → REPORT
  → RELEASE_BROWSER_SESSION (finally, regardless of success/failure)
```

The Controller's READY is infrastructure evidence only. The Skill still
performs target-app reachability, page inspection, and root-cause and fix
verification based on real browser observations. Never auto-fix code on a
connection error. Playwright MCP may help interact only with the **same
authorized browser**, and may not launch a substitute browser after loss.

## 8. Testing and validation matrix

| Test | Expected |
| --- | --- |
| Acquire → real Chrome/MCP → release | READY, then CLOSED; only lease-owned processes stopped |
| Acquire twice, same owner | Same healthy lease, no duplicate Chrome |
| Acquire, another session | `BROWSER_SESSION_BUSY`, owner remains intact |
| Wrong token / forged owner | Rejected; no resource stopped |
| Preoccupied 9222 / foreign Chrome | BLOCKED; no adoption or cleanup of foreign process |
| SSH unavailable / Desktop asleep / GUI absent | NOT_VERIFIED/BLOCKED, no Chrome claim |
| Agent local app `-R` on / off | Browser can access app only when forwarding requested |
| Kill Agent/Plugin without callbacks | Host watchdog reaps lease on expiry |
| Tunnel drops during browser verify | Browser result NOT_VERIFIED, no fallback |
| Skill REPORT vs session.idle vs session.deleted | Immediate release vs grace vs forced release as contracted |
| Start/release races; owner retries | No double allocation, stale owner cannot revoke active lease |
| Prior v1 integration A/B/C | No regression in fix verification or fail-closed |

Evidence must show `systemctl --user` unit identity, loopback bind checks,
both sides of tunnel, Chrome identity, real MCP tool result, and precise
cleanup outcome. Do not mark the design IMPLEMENTATION_READY from command
examples alone.

## 9. Implementation stages / gate

- **Spike 0 — executable contracts**: inspect installed OpenCode v1/plugin
  types and event delivery; validate systemd graphical launch on actual
  Ubuntu Desktop, SSH endpoint ownership and MCP start-before-CDP behavior.
  Resolve gaps as explicit amendments.
- **Stage 1 — Host lifecycle**: restricted `browser-sessionctl`, transient
  Chrome service, exclusive lock, lease store and independent reaper.
- **Stage 2 — Agent controller**: typed commands, SSH management, `-L`/optional
  `-R`, health checks, ownership/rollback, heartbeat.
- **Stage 3 — OpenCode adapter**: tools and lifecycle listeners; test that
  ordinary MCP requests cannot escape acquisition or fail-closed gates.
- **Stage 4 — Skill integration**: concise Skill insertion plus a direct
  reference document; keep existing phases/terminal states.
- **Stage 5 — two-host proof**: normal, duplicate/concurrent, crash, lost
  SSH/MCP, cleanup and A/B/C regression. No master deployment before review.

Ownership and acceptance of each stage must be reviewable independently.
Existing PR #29's fixture repair is a separate change and should not be
silently bundled into this work.

## 10. References and limitations

Repository-grounded baseline:
- `skills/browser-debug-agent/SKILL.md`, `references/requirements.md`.
- `evals/browser-debug-agent/integration/browser-host/start-chrome.sh`.
- `evals/browser-debug-agent/integration/ssh-tunnel/setup-tunnel.sh`.
- `evals/browser-debug-agent/integration/mcp/README.md`.

External contract references (verify against pinned installed versions):
- OpenCode Plugins: https://docs.opencode.ai/docs/plugins/
- Chrome DevTools MCP configuration:
  https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md
- OpenSSH SSH forwarding semantics: https://man.openbsd.org/ssh

This document specifies target behavior; no two-host runtime, hook behavior,
Chrome service, or lease reaper has been implemented or validated by this PR.

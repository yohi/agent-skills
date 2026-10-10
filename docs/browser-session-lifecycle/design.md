# Browser Session Lifecycle Integration — Technical Design

Status: DRAFT / FRESH REVIEW REQUIRED — not IMPLEMENTATION_READY
Date: 2026-10-10 (JST)
Requirements: [requirements.md](requirements.md)
Revision: FDR-030-001 through FDR-030-007; preserve v1 browser debugging contract

## 1. Decision and responsibility boundaries

```text
OpenCode on Agent Host (Ubuntu Server)
   └─ browser-debug-agent Skill (workflow and user-visible entry point)
       └─ OpenCode adapter (trusted owner ID, lifecycle, finalization)
           └─ Agent Controller (exclusive epoch, restricted SSH, health)
               ├─ management SSH (separate constrained key/channel)
               ├─ data SSH -L 127.0.0.1:9222:LEASE_UNIX_SOCKET
               │    [listen only in owned MCP isolation domain]
               └─ official Chrome DevTools MCP (same owning OpenCode instance)
                         │
                         ▼
Browser Host (Ubuntu Desktop / dedicated GUI UID)
   ├─ restricted sshd management/forwarding entrypoints (Tailscale)
   ├─ Desktop Controller (authenticated lease epochs + durable tombstones)
   ├─ lease-unique UDS relay (hard revocation, close accepted streams)
   ├─ per-lease isolated network namespace: Chrome CDP TCP loopback
   ├─ headful Chrome under dedicated GUI user systemd --user unit
   └─ independent systemd --user watchdog / reaper + linger
```

`browser-debug-agent` is the one Skill the user invokes. Chrome lifecycle
and SSH are implemented in separate Controllers; Chrome DevTools MCP remains
the **official browser control implementation**, not replaced by a homemade
CDP stack. The lifecycle relay is **byte transport only**; it must not inspect
or fabricate Console/Network/DOM/Screenshot evidence.

Legacy manual Desktop→Agent `-R 9222` flow is retained only in historical
integration tests. The new deployment intentionally changes the SSH direction
to Agent→Desktop and MUST NOT reuse the old Desktop TCP forwarding target.

## 2. Authoritative identity and CDP isolation (FDR-030-002/004)

**Desktop identity**: a separately provisioned non-admin graphical account
(role label `browser-agent`), distinct from the human's ordinary Chrome user.
The *same* UID owns the graphical login, SSH restricted management session,
`systemd --user` Chrome service, lease store and watchdog. The actual account
name/UID/seat are bound by provisioning and verified at startup; no assumption
that a separate SSH account can control another user's systemd instance.
The restricted SSH key grants only allowlisted typed control requests and
needed lease-bound forwarding. A different SSH UID requires a separate, reviewed
cross-UID broker. Agent forwarding, X11 forwarding, broad SSH shell and sudo
are disabled for AI traffic. If network namespace creation requires privilege,
a pre-provisioned fixed-operation service/helper may be used; normal AI tools
must never receive generic sudo, shell, network-admin or namespace-create power.

**Desktop namespace**: each lease creates a network-isolated Chrome+CDP
environment. CDP is bound to `127.0.0.1:9222` *inside that namespace only*.
It must not be reachable from host/shared loopback. A session-owned TCP↔UDS
relay in the same network namespace connects to Chrome TCP and accepts only
connections on a lease-unique filesystem Unix socket exposed to the
restricted SSH transport. The relay supports arbitrary byte streams/Chrome
WebSockets without interpreting CDP; it must track and kill accepted sockets.
Permissions, dedicated account boundary and a Chrome-private mount view
prevent untrusted Browser Host processes (including Chrome itself) from
opening the SSH-facing socket. Do not claim UID-only checks exclude a
same-UID attacker; the account is dedicated and compartmentalization must
be measured in Spike 0.

**Chrome network access**: a network namespace with only a loopback device
cannot browse ordinary sites. Configure a narrowly provisioned per-lease
egress path (e.g. restricted veth/NAT/user-space networking, with DNS) that
does not expose CDP to another namespace. Browser access to the optional
Agent-hosted app must also be routed/proxied *inside the Chrome namespace*;
a reverse forwarded port on Desktop host loopback alone is not visible
inside that namespace. Do not mark this interface designed-and-proven until
GUI and real application routing are tested on target Ubuntu.

**Agent namespace**: Agent-local TCP `127.0.0.1:9222` is owned by a
separately isolated domain housing the data SSH listener and the *exact
official MCP process* that OpenCode makes available to the owning Skill.
Untrusted shell commands/test processes and other OpenCode sessions, even
under the same login, cannot enter the domain or contact this port. A trusted
launcher/adapter passes MCP stdio to OpenCode without providing arbitrary
namespace entry or a reusable TCP bridge. Fail closed if the installed
Linux/kernel privilege/security configuration cannot enforce this.
`127.0.0.1` is a network scope, never an authorization boundary by itself.

The stated threat excludes compromised root/kernel and theft of explicitly
authorized controller secrets/SSH keys. It **does not** trust unrelated local
applications, test processes or other AI agent sessions.

## 3. Lease identity and owner fencing (FDR-030-001)

Each lease is `(owner_from_adapter, epoch, private_capability)`. The epoch is
a collision-resistant never-reused identifier; the private bearer capability
is stored with restrictive filesystem permissions outside model context.
Names/handles passed to the LLM are non-authorizing. Durable state records
the Chrome unit identity, netns identity, relay unit, socket path, SSH tunnel
PID/process start identity, MCP instance identity, timer and timestamps.

Use a private *per-epoch* filesystem UDS path on Desktop (symbolically
`$XDG_RUNTIME_DIR/browser-lease/<epoch>/cdp.sock`). The directory has 0700
permissions; a retired path is not reused or redirected. SSH local forwarding
targets **that Unix socket** rather than `127.0.0.1:9222` on Desktop:

```text
ssh -L 127.0.0.1:9222:/run/user/<GUI_UID>/browser-lease/<EPOCH>/cdp.sock
```

This is a documented OpenSSH forwarding *shape*, not an executable command:
the actual data SSH process must be started inside its isolated Agent domain
with the restricted identity, flags and optional app reverse forwarding. The
Desktop ingress must be disabled even if the old Agent-side SSH process
persists or restarts. Do not rely on `ExitOnForwardFailure` alone: it proves
the port binding, not ultimate UDS or Chrome reachability. <EPOCH> is a
locally generated identity; never interpolate model-supplied path components.

**Revocation barrier (authoritative Desktop transaction):**
1. Under an exclusive Desktop lease lock, change CURRENT epoch to REVOKING
   and durably commit a revocation tombstone *before* releasing the lock.
2. Relay stops accepting sockets, rejects queued/late connects, terminates
   existing Chrome WebSocket/data streams, closes and unlinks owned UDS;
   network namespace and Chrome unit are stopped.
3. Validate that endpoint, relay and Chrome unit have terminated and remove
   only an owned ephemeral profile.
4. Persist CLOSED/REVOKED terminal epoch. Permit B acquire only once the old
   ingress barrier and cleanup are verified. A incomplete cleanup returns
   CLEANUP_PENDING and blocks successor acquire, including after reboot.

The relay checks authoritative CURRENT epoch before accepting/connecting and
must never rebind a REVOKED socket path. Chrome B uses its **own** namespace and
new UDS endpoint. Thus stale Tunnel A may keep listening at its Agent port,
but remote A socket has no accepting relay and cannot reach B. Include
already-established WebSocket teardown in the acceptance proof.

## 4. Lifecycle API and readiness ownership (FDR-030-007)

These are contracts for future tools, not claims about current OpenCode APIs.

```text
browser_session.acquire(target_url?, agent_app_forward?)
  Owner: trusted OpenCode adapter, never caller-provided
  Success: { state: READY, lease_label, cdp_url: "http://127.0.0.1:9222",
             browser_identity, actual_mcp_instance, epoch_label }
  Failure: { state: NOT_VERIFIED | BLOCKED, code, stage, cleanup_state }

browser_session.status()
  → { state, lease_healthy, tunnel_healthy, mcp_healthy, cleanup_state }

browser_session.release()
  → { state: CLOSED | CLEANUP_PENDING, cleanup_state, code? }
```

Sensitive epoch capabilities, SSH keys, Authorization headers and personal
browser data do not appear in LLM tool results or logs. Labels are not
credentials. Errors include `BROWSER_SESSION_BUSY`, `FOREIGN_ENDPOINT`,
`GUI_SESSION_UNAVAILABLE`, `SSH_AUTH_FAILED`, `CDP_UNAVAILABLE`,
`MCP_UNAVAILABLE`, `TUNNEL_DEGRADED`, `LEASE_REVOKED`,
`ISOLATION_UNAVAILABLE` and `CLEANUP_PENDING`.

Agent acquisition sequence:
1. Verify owning OpenCode execution context and browser intent; exclusive
   adapter lock ensures same-owner idempotency. Reject competing owner.
2. Verify GUI UID/seat, namespace isolation capability, restricted SSH,
   target URL and optional app endpoint. Unknown URL is not inferred.
3. Atomically allocate provisional Desktop CURRENT epoch and own
   Chrome/netns/relay. Prevent inheritance of any personal profile/session.
4. Verify owned Chrome process + CDP browser identity **inside its namespace**;
   provision tested network/app connectivity.
5. Start tracked Agent data SSH in its isolated MCP network/security domain:
   `-L 127.0.0.1:9222:<lease-specific-Desktop-UDS>`, optional tightly
   scoped `-R` for app forward. Check port/process identity on both sides.
6. Verify Agent-isolated CDP endpoint and call `list_pages` through the
   **exact OpenCode-registered official Chrome DevTools MCP instance** that
   the Skill will later invoke. Capture OpenCode MCP instance/process ID,
   owning session, lease epoch and Chrome identity from the same call path.
   A separate probe MCP does not count. Disallow direct/unleased MCP calls
   by process/network gating, not merely by trusting Skill instructions.
7. Commit READY only after step 6. Any mismatch rolls back and revokes lease.

A healthy standalone `curl /json/version` or a separately started
`chrome-devtools-mcp` is *insufficient*. Confirm installation/version and
whether OpenCode can initialize/register MCP after acquire in Spike 0. If it
cannot, implement a tested adapter-owned gating/initialization sequence and
revise the interface; do not falsify READY.

## 5. Health-gated renewals (FDR-030-003)

`READY → IDLE → READY` is a bounded reuse path for the *same* owner/epoch.
Renewals originate from a trusted Agent Controller timer, not a model call.
Each renewal must establish **all**:

1. OpenCode owner still active or within a bounded idle grace.
2. Desktop epoch still CURRENT and unexpired.
3. Correct Agent data SSH PID/start-identity active, **not merely management SSH**.
4. Authoritative Desktop relay socket is CURRENT and reachable through that
   exact SSH tunnel.
5. The owning OpenCode MCP instance completes a bounded health `list_pages`
   against the matching Chrome, not a different MCP process.

Failure stops lease renewal immediately, transitions to DEGRADED with a fixed,
non-extendable recovery deadline and instructs the Desktop to REVOKE as soon
as possible. If transport prevents direct revoke, the pre-existing Desktop
expiry deadline is the backstop. Optional reconnect to the same CURRENT epoch
may be attempted only within the fixed deadline after full rechecks; no
recovery attempt may revive a REVOKED epoch or reuse an old socket for B.
After deadline -> REVOKING/CLEANUP_PENDING. No indefinite retry.

Provisional spike values (not approved operating settings):
30 s heartbeat, 180 s max TTL, 60 s watchdog period, 120 s idle grace, a
fixed recovery budget strictly shorter than the remaining TTL. Deadline/TTL
must use host-side monotonic time while running and durably bounded
wall-clock recovery across reboot; client-reported time is non-authoritative.
Reaper expiry is independent of management SSH health. Browser verification
during DEGRADED is NOT_VERIFIED until a fresh same-epoch MCP proof succeeds.

## 6. Desktop GUI, watchdog, and recovery (FDR-030-004/005)

Desktop `browser-agent` is a dedicated graphical account with an active
authorized login seat. Start headful Chrome via its own `systemd --user`
transient unit, but do not assume SSH `DISPLAY`/`WAYLAND_DISPLAY`/
`DBUS_SESSION_BUS_ADDRESS` values are the GUI session's environment.
Provision/verify the actual GUI user manager's environment and prove a window
opens on the intended seat. Lock screen/logged-out/ambiguous seat is BLOCKED
unless the operator explicitly chooses an approved policy; never silently
log in, unlock or launch headless Chrome.

Provision `loginctl enable-linger browser-agent` (or measured equivalent)
so that the user manager, watchdog timer and revocation authority can operate
after GUI logout. Linger does not create a graphical session. On loss of the
GUI session, new acquire is forbidden; existing lease must enter revocation.
The watchdog owns a persistent recovery journal/tombstone in a private
state directory and independently closes relay ingress then stops the owned
Chrome and cleans owned profile. Its timer and cleanup mechanism must be
tested after logout, manager shutdown/restart and reboot. Restart scans
REVOKING/CLEANUP_PENDING, terminates only verified unit/cgroup identities,
and fences old epochs. If manager failure permits surviving Chrome, an
independent fail-closed termination/ingress revocation must be provisioned;
otherwise implementation is BLOCKED.

User-manager service supervision and permanent credential separation do not
magically guarantee same-UID isolation. The Desktop setup is not approved until
network namespace, socket/mount security, linger and true GUI browser operation
are proven on the target desktop.

## 7. Result finalization and Skill integration (FDR-030-006)

Normal order:

```text
SKILL ACTIVATION
 → adapter ACQUIRE (automated, verified)
 → PRECHECK (target app & real browser)
 → BASELINE → REPRODUCE → OBSERVE → DIAGNOSE
 → [FIX only with explicit authorization] → VERIFY
 → CAPTURE_EVIDENCE → FINALIZE_RESULT (durable)
 → RELEASE_BROWSER_SESSION (adapter-owned bounded action)
 → EMIT_REPORT (final user-visible answer)
```

The agent cannot reliably perform a tool call *after* its final message.
Natural-language `finally` in a Skill is not an execution guarantee.
Therefore the trusted adapter/supervisor coordinates finalization, performs
release before the final response or durably delegates cleanup before
responding, and records `CLEANUP_PENDING` if cleanup fails. Abnormal
termination is handled by the separate Desktop watchdog.

Preserve the browser outcome separately from cleanup outcome:
`FIX_VERIFIED` is legal only on same-browser/same-scenario evidence;
successfully starting a Chrome is never `VERIFIED`. If browser disconnects,
report `NOT_VERIFIED`/`BLOCKED`, with each missing Console/Network/DOM/
Runtime/Screenshot evidence marked `NOT_COLLECTED`. If a fix occurred but
verification did not, use `FIX_APPLIED_NOT_VERIFIED`.

OpenCode `session.idle` is a grace timer signal, not termination;
`session.deleted` attempts immediate release. If these events are not
reliably delivered, the controller/host expiry still closes access.
The installed OpenCode hook payloads and whether actual final replies can be
gated for release are **unknown until Spike 0**. If pre-response release
is impossible, document a durable controller-owned finalization protocol
which releases independently before claiming readiness; no post-response
model-call is accepted as the sole guarantee.

## 8. Negative tests and acceptance matrix

| Test | Required observation |
| --- | --- |
| FDR-030-001: A expired, stale SSH tunnel kept, B starts | Old TCP/WebSockets fail; never hit B; revocation barrier proved |
| FDR-030-001: revoke vs acquire race / restart | Old epoch never resumes; B cannot acquire until barrier completes |
| FDR-030-002: unauthorized Agent/test process | No CDP HTTP or WebSocket access, including same-login test process |
| FDR-030-002: unauthorized Desktop process | No direct TCP CDP or lease UDS access, authorized relay/MCP succeeds |
| FDR-030-002: real Internet/Agent app from namespace Chrome | Web navigation works; CDP still isolated |
| FDR-030-003: kill only data tunnel, management SSH alive | Heartbeats cease; Desktop expires/revokes; Browser NOT_VERIFIED |
| FDR-030-004: GUI UID/SSH UID/user manager comparison | Every component has documented correct UID and seat |
| FDR-030-005: Desktop logout/manager restart/reboot | No new GUI startup; durable cleanup replay; no orphaned CDP |
| FDR-030-006: REPORT interruption/release failure | Durable result + release or CLEANUP_PENDING, before final reply |
| FDR-030-007: probe MCP works but OpenCode MCP fails | No READY; identity of same actual MCP visible in evidence |
| Same-owner duplicate acquire vs different owner | Idempotent same lease vs BROWSER_SESSION_BUSY |
| Port taken by foreign process / partial startup | BLOCKED; never adopt or terminate foreign service |
| Prior Scenario A/B/C | A/B true browser FIX_VERIFIED, C expected fail-closed |
| Unexpected process kill / watchdog reboot | Private tombstone replay + no stale owner access |

Each negative test must be automated as far as technically possible and
supplemented with actual two-host evidence. Unit mocks alone cannot prove
network namespace boundaries, GUI seat ownership, Unix socket lifecycle,
or OpenCode's real MCP process identity.

## 9. Implementation authority and milestones

**Current status: DESIGN_BLOCKED pending independent review + Spike 0**.

- **Spike 0 (no production changes)**: verify OpenCode v1 API, actual
  registered MCP identity and initialization sequence, restricted SSH
  Unix-socket forwarding, process/UID/GUI seat relationships, namespace
  privileges and Chrome Internet/app routing, user linger/logout cleanup.
  Failure to prove any boundary requires explicit design amendment.
- **Stage 1 Host**: lease epochs/revocation journal, namespace Chrome,
  UDS relay, restricted account and watchdog.
- **Stage 2 Agent**: MCP namespace, SSH data/management connections,
  renewal health gates and durable release ownership.
- **Stage 3 OpenCode adapter**: same MCP instance gating, events and final
  response coordination.
- **Stage 4 Skill**: succinct acquisition/finalization instructions and
  progressive-disclosure reference; existing browser v1 workflow preserved.
- **Stage 5 Tests**: all negative cases above and original Chrome A/B/C.

Do not merge PR #29 fixture corrections into this design PR or modify the
historical integration baseline. No implementation or production deployment
is authorized by documents alone.

## 10. Background documentation

- OpenSSH TCP-to-Unix forwarding: https://manpages.debian.org/unstable/openssh-client/ssh.1.en.html
- Chrome DevTools MCP manual connection and loopback risk:
  https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/advanced-usage.md
- systemd user lingering:
  https://www.freedesktop.org/software/systemd/man/latest/loginctl.html
- systemd network namespace capabilities:
  https://manpages.ubuntu.com/manpages/noble/man5/systemd.exec.5.html
- OpenCode plugins: https://docs.opencode.ai/docs/plugins/
- Baseline Skill: `skills/browser-debug-agent/SKILL.md`

Spike 0 must test the **installed versions**; external documentation alone is
not proof that the proposed security and lifecycle controls function on the
actual Ubuntu Desktop and Server systems.

# Browser Session Lifecycle Integration — Technical Design

Status: DRAFT / FRESH INDEPENDENT REVIEW REQUIRED — NOT IMPLEMENTATION_READY
Date: 2026-10-10 (JST)
Requirements: [requirements.md](requirements.md)
Review baseline: FDR-030-001..010 (this revision addresses 008–010)

## 1. Decision: Skill-owned workflow, Broker-owned connections

```text
Agent Host (Ubuntu Server, Tailscale)
  OpenCode / browser-debug-agent Skill
     │
     └─ trusted OpenCode Adapter (session identity and result finalization)
          └─ Agent Broker [separate service UID; owns SSH keys, epoch, origin]
               ├─ official Chrome DevTools MCP [own private netns]
               │   └─ isolated 127.0.0.1:9222 → CDP byte proxy
               ├─ APP gateway [Agent ordinary netns; ONLY approved app origin]
               └─ SSH data client [Agent-originated SSH -T, forced stdio]
                       ║ authenticated, bounded, opaque CDP/APP streams
                       ▼
Browser Host (Ubuntu Desktop, Tailscale)
  sshd restricted transport UID [forced bridge; no SSH port forwarding]
      └─ Desktop Broker IPC [different trusted Broker UID]
           ├─ lease epoch + SSH public-key mapping (private, durable)
           ├─ CDP → revocable lease-unique Unix socket → Chrome netns CDP
           ├─ APP ← lease APP gateway in Chrome netns
           ├─ watchdog/reaper + tombstones independent of GUI user manager
           └─ fixed-operation privileged launcher
                  └─ GUI user manager [dedicated non-admin Chrome UID]
                        └─ headful Chrome [Chrome netns, loopback CDP]
```

One user instruction continues to activate `browser-debug-agent`. The
Skill governs PRECHECK, BASELINE, REPRODUCE, OBSERVE, DIAGNOSE, permitted FIX,
VERIFY, and evidence-based REPORT. The OpenCode adapter/controller owns ACQUIRE/RELEASE, **every-MCP-call
session authorization**, lease lifetime and cleanup. Only the
**official Chrome DevTools MCP** drives Chrome's protocol.

**Architectural correction:** unlike prior Design HEAD `526838aa`, the
data connection does **not** use `ssh -L 127.0.0.1:9222:<UDS>` nor
`ssh -R 127.0.0.1:3000:127.0.0.1:3000`. An SSH client is still started
**only on Agent Host**, but authenticated data is carried in a forced-command
`ssh -T` stdin/stdout stream. Application and CDP destinations are exclusively
selected by authoritative Brokers, not SSH forwarding request parameters.
This keeps the per-lease revocable Unix socket and hard revocation barrier
from FDR-030-001 without assuming OpenSSH can allowlist UDS target paths.

The stdio bridge is a generic binary stream multiplexer, **not** a custom
CDP client, browser-control wrapper or replacement MCP. It must not parse
CDP, HTTP or WebSocket application contents.

## 2. Threat model and principal table (FDR-030-002/004/010)

| Principal / process | Execution authority | Protected resources |
| --- | --- | --- |
| Untrusted Agent OpenCode session / project tests | Normal Agent user; may run test code | Cannot connect directly to lease CDP, read Broker SSH keys/tokens or enter controlled MCP/netns |
| Agent Broker | Separate trusted Agent service UID | Private Agent SSH credential, owner/epoch mapping, APP allowed origins, transport proxy and MCP launch |
| Owning official MCP | Trusted isolated process domain, stdio to owning OpenCode | Only this lease's CDP loopback and tool results; no generic broker/host shell |
| Restricted Desktop SSH transport | `browser-transport` UID with forced stdio command | Cannot read Broker journal/keys or run shell or SSH TCP/StreamLocal forwarding |
| Desktop Broker + reaper | `browser-control` service UID, separately supervised | Exclusive CURRENT/REVOKED epoch authority, secrets, SSH key mapping, UDS relay FD, durable journal |
| Chrome GUI user | `browser-agent` non-admin UID, active Desktop graphical seat | Own isolated Chrome service/profile; cannot read Broker authority or control the relay |
| Privileged fixed-operation launcher | System-provisioned narrow root/privileged boundary | Executes only authenticated, validated GUI start/stop and network/mount namespace operations; no arbitrary command |

**Separate UIDs are required:** the original same-UID GUI/SSH/Broker
assumption is superseded. A 0700 directory does not stop another process
under the same UID. Broker state is not located under the Chrome user's
home/runtime directory; it is in a private Broker-owned system runtime/
persistent state area. Browser Chrome gets a separate mount+network
security view without Broker secret paths, management sockets or inherited
file descriptors. It cannot ptrace or modify a different UID's Broker
process. The Broker IPC authenticates OS peer identity (e.g. `SO_PEERCRED`)
**and** validates authorized operation and CURRENT epoch server-side. A
model-provided lease label is not a capability. The restricted SSH data
principal has no arbitrary shell and is not used to run untrusted workload.

The privileged launcher explicitly mediates the cross-UID boundary.
A Broker `systemctl --user` command does not magically operate the
`browser-agent` GUI manager. The launcher authenticates Broker requests,
looks up the real active GUI seat/UID, validates target unit/profile/netns
and executes fixed operations only. No generic `sudo`, `runuser -c`,
arbitrary shell, user-specified executable or broad `systemctl` access.
Headful Chrome must run as the dedicated GUI UID, not root or the human's
personal Chrome user.

Attacker model includes tests and other OpenCode sessions under the
ordinary Agent login and local Desktop processes (including compromised
Chrome). Trusted Broker/service UID and OS kernel/administrator are outside
the threat model; root/kernel compromise and theft of the authorized
Controller SSH private key are out of scope. Same-login untrusted Agent
processes must not share access to Broker files, MCP netns or proxy listener.

## 3. SSH authorization, wire channels and revocation (FDR-030-001/009)

### 3.1 Data SSH identity

Provision two disjoint restricted SSH principals/key policies:

- **Management principal**: typed `start/status/renew/release` commands
  only, no forwarding and no interactive/general shell.
- **Data principal**: forced `browser-session-bridge` command
  communicating over stdin/stdout. Server-side `Match` and per-key
  restrictions **disable** all OpenSSH TCP and StreamLocal forwarding
  (`-L/-R/-D/-W`, including `-L ...:/path.sock`), PTY, agent/X11
  forwarding, client-selected command execution, SFTP/subsystem and shell.

`PermitOpen` is TCP `host:port` policy, **not** per-lease pathname
Unix socket authorization. `AllowStreamLocalForwarding` selects direction,
not path. A forced command alone is not proof that `ssh -N` cannot create
forward channels; `DisableForwarding=yes` or measured-equivalent
`AllowTcpForwarding=no` AND `AllowStreamLocalForwarding=no` server rules
must be enforced and verified. The data process uses `ssh -T`, no
OpenSSH port forwarding, and binary-clean stdout; diagnostics on stderr.
Connection authentication must be noninteractive and key-scoped.

The authenticated per-lease public-key identity is bound *server-side*
to a single CURRENT epoch, rather than trusting a client-supplied epoch
parameter or a socket pathname. Provisioned `authorized_keys` forced-
command entry / `AuthorizedKeysCommand` may map a key to one epoch, but the
method of safely transferring authenticated key identity to the Broker
MUST be proven on the installed sshd version during Spike 0. Data account
cannot read Broker's mapping. SSH connection to a revoked/other epoch,
or attempts to choose a target, always fail. A model-visible handle,
path or label is never authentication.

### 3.2 Opaque multiplexed transport

An Agent-side controller listener handles local CDP TCP connections only
inside the authorized MCP netns. Each connection becomes an authenticated logical `CDP` byte stream bound
to the ACTIVE connection generation on the Agent-originated SSH stdio transport. Desktop Broker maps it exclusively to the CURRENT epoch's
lease-specific revocable Unix relay, then to Chrome CDP TCP within
the Chrome netns.

Optional `APP` byte streams flow in the opposite direction (see §4).
Framing is versioned, binary-clean and size/concurrency bounded with
per-stream identifiers, OPEN/DATA/CLOSE/ERROR, flow control and timeouts.
Frame type or stream ID does not carry a destination path or arbitrary
host:port. Relay applies backpressure; a malformed frame/unknown
stream type or excess channels fails closed. The bridge does not inspect
CDP/WebSocket/HTTP payloads. It must support concurrent long-lived Chrome
WebSockets and ordinary app HTTP connections. This is a **transport**
implementation, not a browser MCP wrapper.

### 3.3 Atomic revocation and stale-tunnel fencing

Lease identity is `(verified OpenCode owner, unpredictable epoch,
Broker-held credentials, owned process identities)`.
Desktop durable state records GUI Chrome unit/cgroup, Chrome netns,
UDS relay, data SSH key identity, **active data-connection generation and
authenticated connection ID**, accepted streams, APP proxy and
watchdog. The Broker is the sole authority over CURRENT/REVOKING/REVOKED.

Revocation barrier:
1. Under the authoritative lock, persist REVOKING and fence the epoch.
2. Disable both CDP and APP admission; terminate accepted/pending stream
   FDs/WebSockets and associated relay listeners.
3. Close and unlink never-reused per-epoch UDS; stop **owned** Chrome and
   APP gateway/namespace; verify no surviving ingress.
4. Persist CLOSED/REVOKED tombstone and remove only Broker-created owned
   ephemeral profile. Block next acquire until barrier completes.
5. If partial, return CLEANUP_PENDING and let independently supervised
   Broker watchdog retry; never adopt unknown processes or delete a
   personal Chrome profile.

When A expires with its SSH process alive, every A stream remains bound
to REVOKED epoch A; B obtains a different epoch/namespace/UDS. The Broker
cannot route A's streams to B because stream requests contain neither a
destination selector nor authority to switch epoch. An old UDS path is
never reused. Force-stop and timeout must test **existing WebSockets**
as well as subsequent CDP connections.


### 3.4 Active SSH connection generation within one lease (FDR-030-012)

Desktop Broker is the authority for both **lease epoch** and a separate
monotonically increasing **data_connection_generation** with authenticated
SSH connection ID. Broker assigns N+1 only for an authorized same-owner
reconnect within the CURRENT epoch and fixed recovery deadline. Under
a lock, Broker fences generation N, disables its stream admission,
terminates its active/queued CDP WebSockets and APP byte streams, discards
late N frames, and durably records N+1 as ACTIVE. No overlap of two
ACTIVE transports is allowed. Old SSH process/key/epoch is insufficient
to access the new data connection. If N+1 fails, never reactivate N:
use a new N+2 within the original deadline or revoke the epoch.
Broker restart preserves this fence. All OPEN/DATA/CLOSE and heartbeat/
renewal checks require the authenticated CURRENT generation, not PID
liveness alone. The owning MCP must revalidate connectivity after switch.

## 4. Explicit Agent-app path across both namespaces (FDR-030-008)

The test app from historical Integration v1 may run on Agent Host
**ordinary** `127.0.0.1:3000`. That is **not** the loopback of an SSH
or MCP network namespace. Therefore the APP forwarding path is explicit:

```text
Chrome process inside Desktop Chrome netns
  → per-lease APP TCP listener on Chrome-netns 127.0.0.1:3000
  → Desktop Broker (lease-bound APP stream, no destination choice)
  → Agent-originated SSH stdio binary transport
  → Agent Broker (APP stream, origin allowlist)
  → Agent-side APP gateway in **ordinary Agent netns**
  → live Agent app on ordinary 127.0.0.1:3000
  → response along same authenticated stream back to Chrome
```

The trusted Agent Broker holds exactly one explicit per-lease APP target
origin (and acceptable listening port) derived from verified user
request/trusted configuration, not the LLM's arbitrary host commands.
Only this gateway has a route to the approved ordinary netns loopback
app. A data SSH process inside a separate netns cannot directly resolve
that app as its own `127.0.0.1`. No `ssh -R` is required. APP listeners
and channel authorization do not exist if `agent_app_forward` was not
approved. Broker rejects cross-lease streams, mismatched ports, unknown
targets and attempts to dial arbitrary Agent services.

An HTTP redirect returned by the app is passed through as ordinary data,
but does not authorize the gateway to establish a TCP connection to a new
origin. Chrome's independent external browser navigation is governed by
the separately provisioned Chrome netns egress policy. Chrome requires
DNS/HTTPS/Internet access through an explicit restricted veth/NAT or
equivalent path; CDP must stay unreachable outside Chrome netns and
the trusted Broker relay. Mere `PrivateNetwork=yes` with loopback-only
routing is insufficient.

**Acceptance is end-to-end:** run real app in ordinary Agent namespace,
then use actual headful Chrome inside Desktop Chrome namespace to obtain
HTTP 200 and a known body from `127.0.0.1:3000`, while MCP CDP and SSH
retain their isolation. Verify app unreachable on wrong port, no APP when
omitted, malformed stream, source-down behavior, optional WebSockets and
full cleanup. Successful `curl` from the MCP/SSH isolated namespace alone
does not count.

## 5. Agent and Desktop service lifecycle


### 5.1 Mandatory OpenCode session-to-MCP authorization (FDR-030-011)

The network namespace restricts direct TCP access; it does **not** prevent
an unauthorized OpenCode Session B from using Session A's *shared* MCP.
A trusted pre-dispatch guard must run on **every** Chrome DevTools MCP tool
operation, before sending anything to the official MCP process. It reads
the **actual caller session ID** from OpenCode execution context and checks
the authoritative `(caller_session_id, MCP_instance, CURRENT lease_owner,
lease_epoch, ACTIVE_data_generation)` tuple under a consistent ownership
snapshot. Unknown or mismatched IDs, tool aliases, helper/resource
operations if exposed, concurrent B requests and child/subagent sessions
with different IDs are rejected, not silently delegated.

Model arguments, session labels or tool-selected MCP names cannot confer
authority. Reject before dispatch with a typed authorization failure.
Even after successful tool admission, release and generation fencing
must close in-flight CDP streams and revoke further access.

Preferred implementation uses installed OpenCode V1
`tool.execute.before`, **only after proving** that every MCP call
(including aliases, child sessions and concurrent requests) receives an
authentic source `sessionID`, thrown denial aborts tool execution,
and untrusted project hooks/config cannot disable or bypass the guard.
A per-session MCP with genuinely verified session-scoped registration,
routing and OS isolation is an alternate design. A separate MCP process
without call-site isolation is **not** sufficient. If this cannot be
proven in Spike 0, do not enable MCP/READY.

Test: A owns lease; B calls **A's same MCP** `list_pages`,
`navigate_page` and another published operation; B receives denial
before MCP dispatch while A remains usable. Include parallel A/B,
wrong/missing IDs, aliases, child sessions, guard failure, disabled
plugin, direct invocation path and call-vs-revoke race. Audit non-secret
caller ID, call ID, MCP identity, epoch and generation.

### 5.2 Acquire and actual MCP READY

1. Adapter derives authoritative owner from runtime context and **requires
   non-bypassable pre-dispatch authorization** for all MCP tools; without
   a proven guard, BLOCKED. Different owner gets BROWSER_SESSION_BUSY.
2. Agent Broker checks SSH trust, GUI seat, Browser Host identity and
   isolation readiness, plus optional user-authorized APP origin.
3. Desktop Broker allocates provisional unique CURRENT epoch and private
   credential/key binding; fixed-operation launcher prepares Chrome
   namespace, owned relay/app gateway and GUI user-manager Chrome unit.
4. Verify real Chrome CDP/version inside Chrome netns, Chrome GUI UID/unit,
   lease-owned relay and browser network/app egress.
5. Start authenticated Agent-originated forced-command SSH stdio transport,
   plus isolated Agent MCP CDP proxy and optional ordinary-netns APP gateway.
6. The **exact Skill-visible OpenCode-registered MCP instance** must
   invoke `list_pages` **from the lease-owning OpenCode session** through
   the ACTIVE SSH connection generation. Record nonsecret caller, call,
   MCP instance, lease epoch and transport generation. A different diagnostic MCP process does not prove
   READY. If app forwarding is enabled, also validate real end-to-end
   Chrome-netns APP response.
7. Only after these succeed, return READY. Failed stage results in bounded
   compensating revocation, NOT_VERIFIED/BLOCKED and possible
   CLEANUP_PENDING. The Controller's READY never means a UI scenario
   is VERIFIED/FIX_VERIFIED.

Direct MCP calls **before acquire, from Session B while Session A's shared
MCP is READY, or after release** must be blocked by BOTH runtime per-call
session authorization and controller transport/network isolation.

### 5.3 Renewals, session events and cleanup

Renewal requires CURRENT epoch, live owner/grace, Broker-confirmed
**ACTIVE SSH connection generation** and authenticated connection ID,
healthy process, generation-bound CDP roundtrip and bounded call from
owning session's exact MCP. Healthy **management SSH alone**
cannot extend a disconnected data lease. On loss: immediately pause
renewal, enter DEGRADED, begin a non-extendable deadline; optional reconnect
is allowed only to still-CURRENT epoch before deadline with all checks.
Expiry forces revocation regardless of OpenCode/management SSH health.

An independent Desktop **Broker-UID** watchdog maintains durable expiry
and cleanup tombstones and remains operative across GUI user-manager
failure, logout and reboot. `loginctl enable-linger` can keep the dedicated
GUI user manager available for cleanup, but never supplies a graphical
seat when logged out. Browser acquisition requires an actual authorized
GUI login; GUI logout revokes existing lease. Distinct Broker supervision
must itself survive GUI manager exit or recover under system-level
service supervision. It never destroys unowned/unknown Chrome profiles.

### 5.4 Finalization order

```text
Skill activation → ACQUIRE → PRECHECK → BASELINE → REPRODUCE
→ OBSERVE → DIAGNOSE → [FIX with explicit authorization] → VERIFY
→ CAPTURE_EVIDENCE → FINALIZE_RESULT (durable)
→ RELEASE (adapter-owned bounded operation)
→ EMIT_REPORT (browser outcome + independent cleanup outcome)
```

A post-report model call and prose `finally` are not execution guarantees.
OpenCode `session.idle` starts bounded grace, not immediate termination;
`session.deleted` triggers immediate cleanup. Forced process exit and
failed release are handled by durable Broker expiry, preserving
CLEANUP_PENDING separately from browser verification outcome.

## 6. Fresh review acceptance matrix

| ID | Required two-host / negative proof |
| --- | --- |
| FDR-030-001 | Keep A SSH alive, revoke A, acquire B. Old HTTP/WS connections cannot reach B; race and reboot fencing |
| FDR-030-002 | Other Agent login/test processes, other OpenCode sessions and Desktop processes denied CDP HTTP/WebSocket; owning official MCP succeeds |
| FDR-030-003 | Stop data SSH only with management SSH healthy. Renewal stops, Chrome eventually reaped, never false VERIFIED |
| FDR-030-004 | Verify distinct GUI Chrome, Broker, SSH transport UIDs, correct seat and fixed-operation privileged launcher |
| FDR-030-005 | GUI logout, user-manager stop/start, Broker restart and reboot replay cleanup without orphan usable CDP |
| FDR-030-006 | Evidence/result persisted then release before final report, cleanup failure reported distinctly |
| FDR-030-007 | Healthy probe MCP but broken Skill MCP must yield NOT_VERIFIED; compare the exact registered instance |
| **FDR-030-008** | Live Agent ordinary-netns 127.0.0.1:3000 app delivers 200/known body to real Chrome in Desktop netns; forbidden target rejected |
| **FDR-030-009** | With **data and management keys**, deny all SSH -N -L/-R/-D/-W, direct TCP/UDS, SFTP, shell, arbitrary exec, PTY, X11/agent; forced ssh -T stdio works |
| **FDR-030-010** | Chrome UID cannot read Broker key/capability/journal, modify tombstone, open Broker IPC, ptrace authority or reuse other epoch |
| **FDR-030-011** | Session A READY; B's calls to same MCP `list_pages`/`navigate_page`/third tool are denied before dispatch, including concurrent/alias/child attempts |
| **FDR-030-012** | Within same epoch, keep old SSH N alive, connect N+1; N's streams, WebSockets, delayed frames and renewals fail, no dual ACTIVE generation |
| **FDR-030-013** | Requirements §8 and Spike 0 contain only forced SSH stdio, Broker UDS and independent Broker watchdog as normative contract |
| Stdio transport reliability | Real Chrome DevTools MCP long-lived WS and concurrent APP HTTP over binary framing; failure/backpressure/truncation bounded |
| Browser networking | Chrome netns DNS/HTTPS egress; optional APP channel correct; no CDP exposure to shared loopback |
| Existing Integration A/B/C | A/B same-scenario FIX_VERIFIED evidence unaffected; C fail-closed NOT_VERIFIED/BLOCKED |

For SSH authorization, check live `sshd -T -C` and run actual denied
port-forward/StreamLocal attempts: configuration text alone is insufficient.
For same-UID threats, check effective process UID, filesystem, mount
namespace, `/proc` visibility/ptrace, inherited FDs and authenticated
Broker IPC. A real MCP `list_pages` and real Chrome APP HTTP request
are required; mocked unit tests are insufficient.

## 7. Stage gates and limitations

**Design is DRAFT / Implementation NOT_AUTHORIZED.**

- **Spike 0, executable contracts**: prove installed OpenCode V1
  **per-call authenticated session gating on same shared MCP** (including
  child sessions/alias/bypass), same-MCP identity; SSH forced stdio,
  **same-epoch connection-generation fencing**, key/epoch mapping,
  binary transport, GUI launcher, secrets, independent Broker reaper,
  network isolation and Agent ordinary-netns app access.
- **Stage 1 — Desktop**: separate Broker UID, restricted SSH accounts,
  revocable relay, GUI launcher, namespaces and durable watchdog.
- **Stage 2 — Agent**: trusted Broker service, SSH transport, CDP proxy,
  ordinary-netns APP gateway, health and epoch fencing.
- **Stage 3 — OpenCode**: trusted per-call session-to-MCP/epoch/generation
  authorization, aliases/child routing, events and durable finalization.
- **Stage 4 — Skill**: minimal integration instructions plus reference,
  preserving existing browser-debugging semantics.
- **Stage 5 — Acceptance**: all negative cases above and historical A/B/C.

If Spike 0 cannot prove any boundary, remain DESIGN_BLOCKED and revise the
architecture instead of silently permitting generic OpenSSH forwarding,
same-UID Broker secrets or exposed TCP CDP. PR #29 remains separate.

## 8. Relevant upstream specifications

- OpenSSH SSHD policy: https://manpages.ubuntu.com/manpages/noble/man5/sshd_config.5.html
- OpenSSH sshd authorized key controls:
  https://manpages.ubuntu.com/manpages/noble/man8/sshd.8.html
- Linux Unix-domain socket permissions:
  https://man7.org/linux/man-pages/man7/unix.7.html
- systemd isolation:
  https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html
- OpenCode plugin lifecycle: https://docs.opencode.ai/docs/plugins/

Documented intent is **not** runtime proof. The proposed forced stdio
multiplexing, cross-UID launcher, authenticated SSH key-to-epoch handoff
and ordinary-netns app routing still require independent review and a
two-host contract spike on the actual Ubuntu machines.

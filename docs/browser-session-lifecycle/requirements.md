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
| BSL-003 | Agent initiates a lease-bound **SSH -T stdio** transport over Tailscale; Desktop never initiates SSH. Data key rejects generic OpenSSH forwarding. | 2-host transport trace and negative forwarding tests |
| BSL-004 | Browser Host starts **headful** Chrome in the active, authorized graphical login session, using an isolated automation-only profile. | Browser display/session and profile identity |
| BSL-005 | Agent-only MCP netns exposes isolated `127.0.0.1:9222` via an owned byte proxy; authenticated Broker selects a lease-unique Desktop UDS relay. No client-chosen SSH `-L` UDS path. | Namespace and stale-tunnel denial |
| BSL-006 | Optional APP channel connects Desktop Chrome-netns gateway to a trusted Agent gateway in the Agent **ordinary** netns (`127.0.0.1:3000` example); no assumed loopback shared with SSH/MCP namespace. | Real Chrome HTTP 200/known app body and wrong-port denial |
| BSL-007 | READY requires owning-session-authorized `list_pages` on the exact Skill-visible MCP; **every** browser MCP call must match trusted OpenCode caller, CURRENT lease epoch, MCP instance and ACTIVE SSH data generation. | Session B denial with A READY, instance/epoch/generation trace |
| BSL-008 | Repeated acquire by the same owner is idempotent and does not spawn another Chrome/tunnel. | Duplicate calls, same lease |
| BSL-009 | v1 permits one exclusive browser owner per Browser Host; another session gets `BROWSER_SESSION_BUSY` without stealing it. | Concurrent acquisition test |
| BSL-010 | A release stops **only** the authenticated lease's tunnel and Chrome; no `pkill ssh`, broad service stop, or manipulation of personal Chrome. | Process/unit ownership assertions |
| BSL-011 | Adapter persists the result and attempts release **before emitting the final report**; `session.deleted` releases, `session.idle` starts bounded grace. LLM prose `finally` is not an execution guarantee. | Ordered event traces, skipped-release fallback |
| BSL-012 | Agent crash, tunnel loss, forgotten release or Desktop manager failure must revoke Desktop CDP ingress and accepted streams, then reap only owned Chrome without an Agent callback. | Kill -9, tunnel-only failure, timeout and manager restart tests |
| BSL-013 | Agent/Desktop restarts reconcile durable lease epochs, active SSH **connection generations**, authenticated transport identity and tombstones; stale connections/frames never regain authority. | Restart and same-epoch reconnect fencing tests |
| BSL-014 | Chrome unavailability, GUI not logged in, session lock/no access, target app unavailable, port occupied, SSH failure and MCP failure yield typed errors and browser `NOT_VERIFIED`/`BLOCKED`. | Negative scenarios; no browser fallback |
| BSL-015 | Caller can inspect lease status without reading personal browser state. | `status` contract assertions |
| BSL-016 | Explicit release is idempotent and reports partial cleanup as `CLEANUP_PENDING` until confirmed. | Repeated release, failures |
| BSL-017 | A browser-verified outcome requires the original Skill evidence and same-scenario browser recheck; successful acquisition alone never means `VERIFIED`. | A/B/C regression evidence |
| BSL-018 | OpenCode adapter is replaceable but must prove non-bypassable caller-session authorization for **every** MCP dispatch in the installed version; if unproven, BLOCKED. | Runtime negative/tool-hook tests |

## 4. Security / reliability constraints

| ID | Constraint |
| --- | --- |
| BSL-S01 | Dedicated GUI/Chrome UID, trusted Broker UID, and restricted SSH transport UID are distinct. A narrowly provisioned, authenticated fixed-operation privileged launcher performs only approved cross-UID Chrome/namespace operations. No arbitrary shell/sudo/X11 or agent forwarding.  |
| BSL-S02 | CDP endpoints on Desktop and Agent MCP reside in distinct isolated namespaces. Desktop Broker maps authenticated stream type/epoch to revocable UDS relay, not general SSH TCP/UDS forwarding. Other local processes including same-login tests cannot reach CDP.  |
| BSL-S03 | Separate control and data principals; allowlisted management verbs only. Data SSH has forced-command binary stdio and **all SSH generic forwarding**, arbitrary exec/shell, SFTP, PTY, X11 and agent forwarding disabled.  |
| BSL-S04 | Trusted Broker (separate UID from Chrome and SSH transport) owns epoch capability, SSH key mapping, lease state and durable journal. Never place bearer credentials in LLM context or argv/logs; a lease label is not an authorization token.  |
| BSL-S05 | Independent Broker-owned watchdog enforces revocation and durable recovery independent of the GUI account's user manager; linger does not create a GUI session. Callbacks and traps are not the only recovery path.  |
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

- Verify the **installed OpenCode V1** gives a trustworthy originating
  `sessionID` for each browser MCP tool call, including aliases, helpers,
  nested sessions and concurrent calls, and that failed authorization
  prevents actual dispatch. If reliable tool hooks are unavailable, prove
  true per-session MCP publication **and routing isolation**; otherwise BLOCKED.
- Verify READY and later browser actions use the same MCP process, tied to
  CURRENT lease owner, epoch and Broker ACTIVE SSH connection generation.
- Verify Agent-originated SSH **forced-command stdio** (not native
  `-L/-R/-D/-W` TCP or Unix socket port forwarding), authenticated
  key↔epoch mapping and **Broker-mediated** lease UDS/APP stream selection.
- Verify same-epoch reconnect fences old SSH connection generations
  including already-open streams, late DATA frames and heartbeat.
- Verify Agent ordinary-netns APP gateway, Chrome namespace egress,
  separate Chrome GUI/SSH transport/Broker UIDs, fixed-operation launcher
  and real active desktop GUI seat. Independently supervised **Broker
  watchdog** owns revocation and durable replay; GUI user-manager linger
  only supports GUI service lifetime and is not the watchdog guarantee.
- Validate heartbeat, disconnect deadline, TTL and idle grace in real
  two-host tests before selecting defaults.

No production implementation is authorized by this draft.

## 9. Normative remediation contracts — FDR-030-001 through 010

### BSL-019 — Lease-scoped revocation and generation fencing (001)

Each lease has a never-reused epoch and Broker-owned, private Unix relay endpoint.
Agent→Desktop SSH transports opaque streams via **forced-command stdio**
instead of arbitrary `-L` paths; Broker chooses the UDS only from an
authenticated CURRENT epoch. Revocation durably fences epoch, rejects new
streams, forcibly closes accepted WebSockets, stops only owned Chrome and
closes/unlinks UDS. Acquire B is blocked until A's revocation barrier completes.

Test: surviving Tunnel A and active WebSockets cannot contact successor B;
inject expire/acquire races and Broker restart; revoked epochs never revive.

### BSL-020 — Same-host CDP security on both endpoints (002)

Same-login Agent/test subprocesses, other OpenCode sessions and local Desktop
non-controller processes are untrusted, even when loopback is bound.
Chrome CDP resides in a per-lease Chrome netns; owning official MCP and
Agent byte proxy reside in a private MCP domain. Desktop Broker mediates
opaque CDP streams via a revocable lease UDS. No direct TCP/UDS SSH forwarding.
Trusted Broker credentials/state must be protected under separate UID and
restricted mount/IPC domain, never just 0700 in the Chrome UID.
Browser network/APP egress needs separately tested routes.

Test: authorized MCP succeeds; all unauthorized host/agent CDP HTTP/WS,
Unix socket and Broker-management attempts fail, including same-login tests.

### BSL-021 — Heartbeat health gates and bounded reconnect (003)

Renewal requires: current unrevoked epoch, rightful OpenCode owner active
or in bounded grace, **Broker-confirmed ACTIVE data-connection generation**
and matching authenticated SSH connection identity, owned process alive,
CDP connectivity through that connection, and a same-session MCP health call. Successful management SSH by itself is
insufficient. When tunnel health fails, immediately suspend renewals and
declare DEGRADED; bounded reconnect is allowed only to the same unrevoked
epoch, without shifting to another endpoint. A fixed, non-extendable recovery
deadline must expire even if management SSH and the OpenCode session remain
healthy. Reconnection to a revoked epoch is forbidden.

Test: stop only the data tunnel while management SSH and OpenCode stay alive;
Chrome must be revoked and stopped within the loss deadline plus watchdog
interval, and the Skill cannot claim verified browser results.

### BSL-022 — Dedicated GUI user / principal relationship (004)

Dedicated GUI account `browser-agent` owns the graphical seat and Chrome
user unit. **Different** Broker UID `browser-control` owns lease secrets,
journal, relay and watchdog. Separate `browser-transport` SSH UID runs only
restricted forced command. A pre-provisioned fixed-operation privileged
launcher performs authenticated cross-UID GUI/namespace setup without arbitrary
shell. SSH user manager is not assumed to be GUI user manager.

Test: verify actual SSH/Broker/Chrome/launcher UIDs, IPC authorization and
GUI seat; no Chrome access to Broker authority.

### BSL-023 — Watchdog lifetime and GUI logout (005)

Independent Broker-UID watchdog owns durable tombstones and replays revocation
after GUI user-manager stop/restart, logout and reboot. GUI linger preserves
manager only, not a graphical login. Logout blocks fresh acquisition and
revokes prior data channels. B cannot acquire until old ingress is fenced.

Test: manager shutdown/re-login/Broker restart leave no orphan usable CDP.

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

READY requires `list_pages` from the actual OpenCode-registered Skill MCP
called by the owning OpenCode session, not a probe. Bind **each** MCP call
to verified caller session, registered instance, CURRENT epoch and ACTIVE
data generation, reject other sessions **before dispatch** and revoke
existing streams when access ends. Network isolation does not authorize a
shared MCP's tool callers.
The installed OpenCode version's hooks, stdio registration, initialization
order and client routing must be demonstrated by a contract spike.

Test: a separate test MCP succeeds while the Skill-registered MCP is broken;
READY must fail. Compare instance/epoch identity for probe and actual calls.

### BSL-026 — Implementation authorization gate

All thirteen corrections must pass independent Design Review and the real
two-host contract spike before implementation is authorized. Inability to
prove the host GUI/namespace/egress model, localhost CDP isolation,
SSH forced-command authentication, Broker separation, Agent APP routing,
OpenCode gating/instance identity, or
manager cleanup is DESIGN_BLOCKED, not a reason to reduce security requirements.

### BSL-027 — Agent ordinary-netns APP gateway (FDR-030-008)

When an Agent-loopback app is explicitly requested, a separate trusted Agent
APP gateway in the **ordinary Agent netns** connects to a single configured,
validated endpoint (e.g. `127.0.0.1:3000`). Desktop Chrome has a per-lease
APP listener **inside Chrome netns**. Opaque APP byte streams travel via
the same Agent-originated SSH stdio transport to Agent Broker and this
ordinary-netns gateway. The isolated MCP/SSH namespace's own loopback is
not the application; `ssh -R` is not an implicit solution. Broker, not the
browser, model or SSH peer, selects target host/port. If not authorized no
APP channel/listener exists. Ordinary HTTP redirects do not authorize a new
gateway origin.

Acceptance: actual Agent app in ordinary netns returns HTTP 200 plus a
known body to real Chrome in Desktop netns. Validate denied wrong port,
missing app, unrelated Agent network services, WebSocket and redirects;
ensure CDP isolation is unchanged.

### BSL-028 — SSH destination authorization (FDR-030-009)

Do **not** rely on `PermitOpen`/`permitopen` to authorize a Unix
socket path. Data SSH authenticates a per-lease key mapped **server-side**
to CURRENT epoch and executes one forced binary-clean stdio bridge
(`ssh -T`). Server config **disables all** TCP and StreamLocal local/
remote forwarding, `-L/-R/-D/-W`, arbitrary exec, shell, subsystem/SFTP,
PTY, agent/X11 forwarding. `ForceCommand` alone cannot gate `ssh -N`
port-forward channels. Control key/principal is separate and likewise has
no generic forwarding. Broker accepts bounded `CDP` and approved `APP`
opaque stream types, not arbitrary UDS paths/host/port. Bridge implements
no CDP parsing; binary framing handles concurrent streams/backpressure.

Acceptance: actual OpenSSH `sshd -T -C` and malicious connection matrix
for data/control keys deny every unwanted forwarding/exec kind; only
authenticated forced stdio transports a real MCP WebSocket and APP HTTP.
Old SSH/key/epoch denied after revocation.

### BSL-029 — Cross-UID secrets and journal boundary (FDR-030-010)

The Chrome GUI UID, restricted SSH transport UID and trusted Controller
Broker UID are different. Broker-owned journal, private capabilities,
per-epoch key mapping, relay management handles and durable tombstones
are unreachable/unmodifiable from Chrome, unauthorized desktop processes
and Agent test processes. Same-UID 0700 alone is insufficient. The
Broker IPC checks kernel peer identity **and** server-side permitted
operation/epoch. Fixed-operation privileged launcher cannot execute
model-supplied commands or expose unrestricted `systemctl`/sudo.

Acceptance: as Chrome GUI UID and arbitrary non-Broker process, attempts
to read tokens, alter durable state, connect to management IPC, reach
other relay, ptrace/read private /proc state or use stolen epoch labels
are rejected. Test filesystem owner/mode, namespace/mount, inherited
FDs, peer-credentials and process separation. Broker continues cleanup
when GUI manager exits.

### BSL-030 — Spike and authorization gate (008–013)

Requirements and design do not prove implementation feasibility. Independent
Fresh Review is required, followed by executable Spike 0 on both actual
hosts: SSH forwarding denial + forced stdio, authenticated key-to-epoch
mapping, binary HTTP/WebSocket, Agent ordinary-netns APP reachability,
Browser Chrome netns egress, GUI cross-UID launcher, Broker authority
separation and OpenCode same-MCP identity. If any cannot be proven,
DESIGN_BLOCKED; no insecure loopback/UDS/general forwarding fallback.

### BSL-031 — Enforce session ownership on all MCP calls (FDR-030-011)

Every Chrome DevTools MCP tool invocation MUST be authorized *before its
MCP request is dispatched*. A trusted OpenCode runtime source, not model
arguments, supplies calling session ID. Atomically require: caller equals
CURRENT lease owner; target is the exact registered MCP instance; lease epoch
is CURRENT, transport generation ACTIVE and browser access authorized.
Apply to all browser tools, aliases, MCP resources/helpers if registered,
parallel calls and distinct child/subagent sessions; no implicit inherited
owner privileges. Unrecognized tools, missing identity, unguarded/bypassing
entrypoints or failure to install the mandatory guard deny access. A shared
MCP process's isolated TCP listener does NOT by itself authorize a second
OpenCode session to call that MCP. Revoke in-flight streams on lease loss.

Preferred: installed OpenCode V1 `tool.execute.before` with trustworthy
`sessionID` and tested throw-aborts-dispatch semantics plus protected hook
order. Alternative: proven truly **per-session MCP publication and routing**
with equivalent enforcement. If both unavailable, do not expose MCP and
return BLOCKED; upstream code alone is not execution proof.

Acceptance: while A owns READY, B calls A's **same** MCP `list_pages`,
`navigate_page` and another operation; each fails before MCP activity and
A still works. Test missing/forged IDs, simultaneous A/B, MCP tool aliases,
subagent sessions, guard disabled/bypassed/overridden, and release vs call
race. Record non-secret call/session/MCP/epoch/generation identity.

### BSL-032 — Fencing same-epoch SSH reconnects (FDR-030-012)

Desktop Broker stores the durable, monotonically incremented
`(lease_epoch, active_data_generation, authenticated_connection_id)`.
Each stream frame and renew requires matching authenticated ACTIVE
generation, not just a CURRENT epoch or living SSH PID. Reconnection must
first durably fence generation N, reject its queued/new frames and close
its existing APP/CDP streams/WebSockets; only then may N+1 become ACTIVE.
Two data transports cannot simultaneously operate, even if old SSH
remains running. A failed N+1 never reactivates N; only a new generation
within unchanged lease expiry/loss deadline may retry, or epoch expires.
New connection requires same-owner authorization and fresh MCP/browser
health. Reject old generation heartbeat or release authority.

Acceptance: hold old SSH N alive when N+1 connects in same epoch;
old new streams, delayed DATA, existing WS and heartbeats all fail.
Inject concurrent reconnect, failed N+1 and Broker restart/replay.

### BSL-033 — Consistency of transport and watchdog (FDR-030-013)

Normative design and Spike 0 use *only* authenticated SSH forced-command
stdio transport and **Broker-selected** lease UDS/APP streams, not
`PermitOpen` path allowlisting or generic OpenSSH forwarding. Broker
watchdog has independent service supervision and durable revocation;
GUI user-manager linger is not the primary cleanup guarantee.

Acceptance: inspect §8, Design and Spike 0 for any contradictory live
SSH forwarding, ownership, UID or watchdog contracts. Historical
superseded designs may be mentioned only as explicit non-goals.

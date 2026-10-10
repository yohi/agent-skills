# Spike 0 — Executable Contract Verification Plan

Status: **PLAN READY FOR INDEPENDENT REVIEW; EXECUTION NOT_STARTED**
Date: 2026-10-10 (JST)
Scope: **Evidence-producing prototype/spike only; no production implementation**
Design gate: **Fresh Design Review PASS; Spike 0 AUTHORIZED; Production Implementation NOT_AUTHORIZED**
Review-approved Design commit: `59a76977c4217278df2791efdb6fd0ccd053e820`
Design metadata-only follow-up: `840a5ea024bbc70fa3b7950754f6909eddee7874`
Frozen Requirements blob: `c3bbabab28d45895d75daae1d463d29522d6e6d7`
Frozen Design blob: `559fe58ac0cd99c995d57cccdac982e6e2831b1b`
Repository: https://github.com/yohi/agent-skills/pull/30

## 1. Objective and boundary

**Objective:** prove or disprove the executable preconditions in
[Requirements](requirements.md) BSL-001..033 and
[Technical Design](design.md), with particular focus on FDR-030-001..013.
Do not mistake a source-code inspection, mock/unit test, configuration text
or successful TCP connection for actual two-host proof.

An AI agent running on **Agent Host (Ubuntu Server)** leads execution.
**Human operator** grants bounded approvals/physical GUI interaction and
pre-provisions authorized test identities where required.
**Independent reviewer (ChatGPT or a separate agent, not the executing
agent)** evaluates committed design obligations against unedited evidence.

The v1 historical Integration harness in
`evals/browser-debug-agent/integration/` proves *manual* Desktop→Agent
Chrome/SSH operation only. It does NOT prove the new Agent→Desktop
forced-command stdio/Broker/namespace architecture. PR #29's reusable
fixture work is a separate change; run regression on a verified buggy
baseline, never silently use already-fixed fixtures.

This plan authorizes **disposable, isolated contract probes**, scoped
test programs and negative tests. It does not authorize modifying
`skills/browser-debug-agent/SKILL.md`, merging production Controllers,
deploying permanent host services, opening CDP on network interfaces,
changing the user's personal Chrome profile, or upgrading OpenCode/Chrome
without explicit approval.

## 2. Frozen proof conditions and prohibitions

- Recheck HEAD, Design/Requirements blobs, PR base and approved review
  before each new execution batch. If the reviewed contract changed,
  mark `BASELINE_CHANGED`; do not silently revise assertions.
- All SSH connection attempts originate at Agent Host. Test-only sshd
  should run on an **alternate, explicitly allowed port** with isolated
  temporary config/keys, leaving production sshd untouched. No `ssh -L`,
  `-R`, `-D`, `-W` or StreamLocal native forwarding in a *candidate
  successful* design; use them only as **negative tests**.
- CDP must remain unexposed to LAN/Tailscale and to unauthorized local
  processes. Loopback alone is not an authorization test. Never reuse a
  personal Chrome profile or terminate unrelated ssh/Chrome.
- Browser Host identities are separate: trusted `browser-control` Broker
  UID, restricted `browser-transport` SSH UID, and dedicated
  `browser-agent` headful GUI Chrome UID (actual names/UIDs discovered
  and approved, not assumed). Agent trusted Broker/launcher likewise
  must not share secrets or privileges with untrusted project tests.
- Use a separate disposable working directory, test-only user accounts/
  namespaces, non-production ports and ephemeral credentials. Do not
  register permanent units, change live sshd config, enable lingering,
  modify PAM, modify firewall or add sudo/privileged policy without human
  approval of the exact command/change and rollback. Never auto-login or
  unlock a desktop.
- The existing Skill's FIX authorization remains separate: Spike 0 cannot
  modify application source unless the human authorized that *particular*
  controlled test. No business data or private browsing.
- Before a disruptive test (logout, restart/reboot, kill -9, network
  partition, service stop, user/group changes, namespace/route mutation),
  record target PID/unit/namespace and blast radius, then obtain explicit
  human approval. Prefer disposable VMs/cgroups for fault injection.
- No secret-bearing outputs: redact private keys, auth tokens, HTTP cookies,
  usernames/addresses not needed to prove behavior, URL query secrets and
  session storage. Use hashes or public-key fingerprints where possible.
- An anticipated failure is acceptable evidence of a failed hypothesis,
  but never describe `NOT_PROVEN` or `BLOCKED` as PASS.

## 3. Actors, execution locations and gates

| Role | Responsibility |
| --- | --- |
| AI agent — Agent Host | Own run ID, frozen baseline, controlled probes, command execution where permitted, evidence/manifest, cleanup, honest verdict |
| Human operator | Approve scoped temporary privileges, dedicated GUI account, test sshd port, cross-UID service setup, GUI login, network mutations, intentionally disruptive tests; perform interactive Desktop steps |
| Independent reviewer | Review evidence and negative controls per requirement; demand replay where missing; decide spike findings without accepting self-claimed success |
| Desktop Broker/Agent Broker probes | Temporary experimental programs only; never privileged authority without operator-approved fixed-operation boundary |

**Gate 0 — Non-invasive:** SP0-00/01 can run read-only without elevation.
For any inaccessible file/host or uninstalled dependency, record
`BLOCKED` and the smallest requested operator action rather than
silently trying privileged access or changing production state.

**Gate H — Operator approval:** before SP0-02+ network/login/account/
systemd/sshd changes, submit the exact affected host, identity, commands,
paths/ports, security impact, rollback and expected lifetime.
An AI agent cannot self-approve this gate.

**Gate R — Independent evidence review:** after all runnable probes,
compare each BSL/FDR obligation to a corresponding live test result.
A successful Spike 0 is *not* authorization to deploy or merge production
implementation. Design amendments go back through review.

## 4. Execution dependency graph

~~~text
SP0-00 Freeze + inventory (read-only)
  ├── SP0-01 OpenCode same-MCP session dispatch (read-only/test local)
  ├── SP0-02 SSH forced-command / authenticated identity (operator gate)
  └── SP0-03 Trust principals + namespace feasibility (operator gate)
             │
             └── SP0-04 GUI Chrome & broker separation
SP0-02 + SP0-03 ──> SP0-05 stdio stream / epoch + generation fencing
SP0-03 + SP0-04 + SP0-05 ──> SP0-06 CDP isolation & revocation
SP0-05 + SP0-06 ──> SP0-07 APP gateway + Chrome egress
SP0-01 + SP0-06 + SP0-07 ──> SP0-08 exact-MCP READY / lifecycle
SP0-05 + SP0-06 + SP0-08 ──> SP0-09 failure/watchdog/finalization
SP0-08 + SP0-09 ──> SP0-10 v1 A/B/C compatibility (fixture-ready only)
all probes ──> SP0-11 report / independent review
~~~

Do not start a downstream live integration test when a prerequisite
authority boundary is `NOT_PROVEN`/`BLOCKED`; a safe isolated
sub-probe is allowed but must **not** imply downstream proof.

## 5. Execution tasks

### SP0-00 — Freeze baseline and discover host inventory

**Location:** Agent Host, read-only SSH queries to Browser Host if already
permitted. **No permissions change.**

Actions:
1. Record repository/PR HEAD, Design and Requirements **blob SHA**, working
   tree cleanliness and any deviation from the approved references above.
2. Discover effective OS/kernel/distribution, OpenCode executable/version
   and resolved plugin/config sources, Node version, SSH/sshd version and
   effective policies *without dumping credentials*; inventory Chrome
   executable/version, GNOME/Wayland or X11, systemd user-manager/seat
   and Tailscale SSH reachability on both hosts.
3. Record test app location and ordinary Agent loopback listener ownership,
   existing CDP/app port owners (do not kill/rebind), and any prohibition
   on locally isolated processes (AppArmor, SELinux, user namespaces).
4. Separate observed facts from design assumptions. Construct operator
   approval requests for additional test accounts/privilege.

**PASS evidence:** dated sanitized inventory, resolved binary versions,
actual connection direction, permissions and capability list.
**BLOCKED:** no authorized connectivity, unverifiable installed version,
or conflicting protected service. No speculative substitutions.

### SP0-01 — OpenCode MCP *per-call* session authorization (BSL-007/031)

**Location:** Agent Host, disposable OpenCode configuration/session pair.
**Dependency:** SP0-00. Avoid using private production conversations.

1. Discover installed OpenCode V1 plugin SDK and actual MCP tool dispatch
   paths; record the exact package/version/hash and hooks that run before
   dispatch. An upstream GitHub code sample alone is insufficient.
2. Register one disposable official MCP server and create **two independent
   OpenCode sessions A and B** in the same runtime. Establish a controlled
   fake/isolated browser endpoint only for *hook* proofs (NOT real-browser
   READY). Instrument whether a tool reaches MCP.
3. Test `tool.execute.before` or a version-verified equivalent with
   authoritative `sessionID` and an injected rejection. Calls from A
   should reach MCP after authorization. B must be refused **before** MCP
   dispatch for `list_pages`, `navigate_page` and another published
   browser operation, even when the MCP instance is shared.
4. Enumerate and attack all actual dispatch paths: aliases, MCP resources/
   helpers, parallel calls, nested/subagent sessions, absent/forged context,
   direct client routes, plugin failure/load ordering and untrusted
   configuration override. Confirm the guard cannot be disabled/bypassed
   by the lower-trust test project.
5. Verify revoke-vs-dispatch behavior: new requests denied and an
   already-admitted in-flight call cannot continue browser I/O once the
   underlying transport has been fenced (use an isolated transport probe).

**PROVEN only if:** the **installed runtime** supplies verified session
identity and a non-bypassable gate across all reachable operations, with
actual MCP invocation traces. Per-session independent publication/routing
is an acceptable alternative only if *proven*.
**BLOCKED:** any unguarded call path or weak caller provenance. Record
the alternative required design amendment rather than installing a
different OpenCode version silently.

### SP0-02 — Restricted SSH stdio and authenticated epoch mapping (BSL-028)

**Locations:** test sshd on Browser Host; Agent-originated client.
**Dependency:** SP0-00 + human Gate H for any sshd/key/account changes.

1. Use an isolated sshd instance/port and **two distinct test principal/
   key policies**: allowlisted management and forced-command data.
   Determine authenticated key identity-to-lease binding available in the
   actual sshd (e.g. controlled authorized-keys mapping); do not assume
   a client-provided label/SSH_ORIGINAL_COMMAND is authentic.
2. Observe effective `sshd -T -C` and authenticated connection behavior.
   Confirm no arbitrary commands, SFTP, PTY, X11/agent forwarding or
   arbitrary TCP/StreamLocal forwarding for **both** principals.
3. Explicitly attempt rejected `ssh -N -L/-R/-D/-W`, direct-to-UDS
   and StreamLocal forwarding. A forced command alone is NOT a proof.
4. Exercise `ssh -T` binary stdin/stdout with null bytes, large frames,
   bidirectional flow, interruption and connection close. Attribute every
   accepted connection to the SSH-authenticated key and CURRENT epoch in
   trusted Broker observations, not just the request body.
5. Rotate/revoke mapping; test stale key, forged epoch, parallel control
   and data credentials, and that revoked SSH transport cannot regain
   Broker stream authority.

**PROVEN:** actual negative SSH operations are denied and only
authenticated bounded stdio bridge works with an unforgeable key→epoch
binding. **BLOCKED:** unsafe sshd policy or indistinguishable SSH identity.
Restore test config/keys before concluding.

### SP0-03 — Principal, mount/netns and Broker authority feasibility (BSL-S01..S05/020/022/029)

**Location:** both hosts in isolated lab security domains.
**Dependency:** SP0-00 + human Gate H.

1. Determine whether the three distinct Desktop roles (GUI Chrome,
   SSH transport, Broker) and Agent trusted Broker versus untrusted
   OpenCode/tests can exist with the proposed privileges.
2. In disposable namespaces verify process UID, mount/netns IDs,
   filesystem controls, `/proc`/ptrace visibility, inherited FDs and
   peer-credential-based Broker IPC. Simulate forged lease labels.
3. As Chrome UID and unauthorized test processes, try **reading**
   Broker credentials and durable journal, **modifying a disposable**
   tombstone, connecting Broker management IPC/UDS and reaching CDP.
   Denials must be observed, not inferred from directory mode alone.
4. Verify the fixed-operation launcher can authorize *specific*
   Chrome/netns/unit operations without any model-provided shell command,
   unrestricted sudo, or allowing test code to enter MCP netns.
5. Confirm Chrome netns external DNS/HTTPS egress is feasible without
   leaking CDP to Desktop shared loopback.

**PROVEN:** attempted unauthorized accesses fail and legitimate Broker
actions succeed with recorded actual UIDs, process/mount/network context.
**BLOCKED:** same-UID secret accessibility or unbounded privilege.
Never test access to the real user's private files.

### SP0-04 — Headful Chrome GUI user service and lifecycle (BSL-004/022/023)

**Location:** Browser Host in an explicitly approved live GUI session.
**Dependency:** SP0-03 plus operator's GUI account/seat provisioning.

1. Verify active graphical **login of the dedicated GUI UID**, actual
   seat, Wayland/X11 and systemd user-manager environment; distinguish
   the restricted SSH principal from the GUI owner.
2. Through the approved fixed-operation launcher, start a *temporary,
   owned* headful Chrome user unit with a new private automation profile
   and CDP only on namespace loopback; record actual window and process
   unit/UID/netns. Do not use the personal Chrome profile.
3. Check headful browsing, active graphical session and user-manager
   ownership. Do not silently use headless Chrome on failure.
4. Validate shutdown/cleanup **only of the test unit/profile**.
   Logout, manager failure and reboot tests are reserved for SP0-09.

**PROVEN:** Chrome window on intended Desktop seat, correct GUI UID,
correct cgroup/service identity, isolated CDP and owned cleanup.
**BLOCKED:** sshd account can only launch its *own* user manager, GUI
session is unavailable, or Chrome starts outside isolation.

### SP0-05 — Binary stream and same-epoch data generation (BSL-019/021/028/032)

**Locations:** Agent and Desktop lab Brokers; only test data.
**Dependency:** SP0-02/03. No production controller installation.

1. Build the **smallest throwaway byte relay prototype** necessary to
   prove framed/flow-controlled `CDP` and `APP` streams over the
   authenticated SSH stdio connection. No custom CDP/browser semantics.
2. Test binary payload integrity, long-lived TCP/WebSocket, simultaneous
   streams, backpressure, malformed/truncated/oversized frames,
   reconnection timeouts and bounded resource usage.
3. Assign epoch E with Broker-minted ACTIVE SSH generation N and
   authenticated connection ID. Keep N alive, stage N+1 and fence N
   before admitting N+1 traffic. Assert old active WS, late DATA,
   queued frames and old heartbeat fail, despite live N PID/key.
4. Inject concurrent reconnects, crashed N+1, Broker restart/replay,
   wrong generation release and a rejected stale epoch; never restore
   N or lengthen original expiry deadline.

**PROVEN:** captured per-generation Broker transitions plus actual
negative old-stream/heartbeat traces; generic application byte transport
works without interpreting CDP. **NOT_PROVEN:** only unit/mocked streams
or simultaneous N and N+1 active.

### SP0-06 — Lease-unique UDS, CDP isolation and hard revocation (BSL-005/019/020)

**Locations:** both hosts, real isolated Chrome from SP0-04.
**Dependency:** SP0-04/05.

1. Expose Chrome CDP only in Browser Chrome netns, through Broker-selected
   unique UDS relay, SSH authenticated stream and isolated Agent MCP CDP
   listener. Prove it is not reachable from Agent ordinary namespace or
   non-Broker Desktop processes via TCP, Unix or WebSocket.
2. Start lease A, open a real CDP WebSocket, stop Agent heartbeat and leave
   A's SSH process alive. Desktop Broker independently revokes A and
   closes active WebSocket/pending streams.
3. Create B **only after the A revocation barrier**. Probe stale A's
   SSH/data connection/UDS and verify it cannot read or drive B.
4. Race expiration vs acquire, restart Broker with tombstone, test foreign
   port owner and ensure no unrelated Chrome/SSH process is killed.

**PROVEN:** actual negative access to B from stale A and unauthorized
local processes, with no shared namespace CDP exposure.
**BLOCKED:** an old SSH/UDS tunnel can access successor Chrome.

### SP0-07 — APP origin and Chrome network egress (BSL-006/027)

**Locations:** Agent ordinary netns application; Browser Chrome netns.
**Dependency:** SP0-05/06.

1. Start a **controlled test-only app** bound on Agent Host ordinary
   `127.0.0.1:3000` (or approved alternate port if occupied).
   Verify its owning PID and an unmistakable response marker.
2. Configure exactly one authorized APP gateway in Agent ordinary netns,
   Broker-authorized SSH APP channel and per-lease listener inside
   Desktop Chrome netns. Do not use native `ssh -R`.
3. From the **real Chrome window / owning MCP path**, request the
   Chrome-netns listener and prove HTTP 200 **and body marker** arrived
   from the actual Agent app. Check relevant DNS/HTTPS navigation.
4. Deny wrong Agent port/host, omitted APP authorization, cross-epoch
   reuse and unauthorized arbitrary destinations. Test basic HTTP
   redirects/WebSocket only through the expressly approved route.

**PROVEN:** real Chrome → Desktop netns APP → SSH stdio → Agent ordinary
netns app evidence, plus denied unauthorized origin and CDP isolation.
**NOT_PROVEN:** curl from SSH/MCP namespace alone.

### SP0-08 — End-to-end exact-MCP READY and Skill ownership (BSL-001/002/007/018/025/031)

**Locations:** Agent OpenCode V1 and Browser Host authorized lab Chrome.
**Dependency:** SP0-01/06/07.

1. Exercise `browser_session.acquire/status/release` through a temporary
   test adapter using **actual OpenCode execution context**, not LLM
   supplied session ID. The adapter may be throwaway; do not edit the
   versioned Skill or claim production integration.
2. Establish that `list_pages` used for READY is invoked via the
   **exact OpenCode-managed official MCP instance** exposed to Session A
   and passes per-call owner/epoch/generation checks.
3. Simultaneously ask Session B to invoke A's exact published browser MCP
   `list_pages`, `navigate_page` and another real tool. Confirm denial
   before MCP dispatch; A continues normally.
4. Make the Skill-visible MCP fail while a separate diagnostic MCP
   succeeds. READY MUST be denied. Make the guard fail to load: MCP
   must not be published as usable. Check wrong caller IDs and direct
   resource/helper invocation paths.
5. Release once, release twice, and verify no unauthorized browser call
   works after release. Evidence must separate infrastructure READY
   from actual browser VERIFY/FIX_VERIFIED.

**PROVEN:** real MCP instance/session/call identity, A allowed, B rejected,
guard failure fail-closed and no post-release browser access.
**BLOCKED:** installed OpenCode cannot reliably bind source session to MCP.

### SP0-09 — Watchdog, abnormal exit and report finalization (BSL-010..017/021/023/024)

**Locations:** both hosts; fault injection in isolated lab.
**Dependency:** SP0-05/06/08 + **specific human approval** for each
disruptive failure test.

1. Start authenticated lease and suspend only data SSH while leaving
   management SSH and OpenCode active. Confirm heartbeat/renewal stops
   (checks active data generation, not management reachability) and
   Desktop Broker revokes CDP by deadline independently.
2. SIGKILL only an **identified test Agent/controller process**;
   ensure watchdog reaps its Chrome/APP/UDS and the tombstone records
   incomplete cleanup/retry; no broad `pkill`.
3. Test GUI logout, GUI user-manager stop/start, Broker watchdog
   restart and reboot **only on disposable or operator-approved lab
   environment**. Independent Broker service must preserve/recover
   authority and reject successors until old ingress is fenced.
4. Verify `session.idle` starts only bounded grace and
   `session.deleted` triggers release. Simulate failure between
   CAPTURE_EVIDENCE, durable FINALIZE_RESULT, RELEASE and EMIT_REPORT;
   no after-report model tool call is presumed.
5. Confirm `NOT_VERIFIED`/`BLOCKED`/cleanup status and NOT_COLLECTED
   evidence remain distinct from browser diagnosis.

**PROVEN:** event and state timelines, finalization order, independent
cleanup on crash/logout, stale access impossible and no personal
Chrome/SSH effects. **BLOCKED:** only callback-based cleanup.

### SP0-10 — Historical browser-debug-agent regression (BSL-017)

**Location:** isolated evaluation worktrees and real Chrome.
**Dependency:** SP0-08/09, reproducible fixture baseline from PR #29.

1. Verify the chosen fixture Git revision reproduces Scenario A
   `POST /api/settings` 500 and Scenario B dashboard exception, before
   permitting each scenario's source repair. Do not assume master has
   incorporated PR #29; name exact fixture commit/worktree.
2. Repeat Scenario A/B with explicit FIX authorization, minimal repairs
   performed only in disposable worktrees, and true Chrome/MCP VERIFY.
3. For Scenario C, drop the **owned test data transport only** and
   confirm the Skill says `NOT_VERIFIED` or `BLOCKED`, not `VERIFIED`.
4. Preserve original Skill phases and evidence/terminal outcome contract;
   distinguish a spike test adapter from a production-ready Skill change.

**PROVEN:** fresh real-browser evidence and exact fixture/source hashes;
historical report alone does not prove the new transport. If time/approval
is unavailable, mark `NOT_RUN` and leave overall Spike 0 incomplete.

### SP0-11 — Evidence publication and independent Review Gate

**Locations:** Agent Host produces bundle; independent reviewer consumes.
**Dependency:** finish or explicitly stop each task.

1. Produce one immutable run manifest with design blob SHAs, run ID,
   per-host tested package versions, identities, timestamps, test commands,
   exit codes and hashes of redacted evidence files. Record each test's
   assumptions, intended operation and observed OS/network result.
2. For each FDR-030-001..013 and BSL-019..033 map **specific** task/test
   cases, evidence filename+sha256, failure injection, result and gaps.
   Include BSL-001..018 / security constraints in coverage summary.
3. Include all negative tests, aborted tests, inaccessible-host evidence,
   privileges actually used, resource cleanup status, and operator approvals
   by non-secret reference. Do not backfill mock output as live proof.
4. Report `PROVEN`, `NOT_PROVEN`, `BLOCKED`, `NOT_RUN` or
   `INDETERMINATE` **per obligation**. Global
   `SPIKE_PROVEN` requires every mandatory obligation PROVEN plus clean
   environment teardown. A partial spike stays `SPIKE_INCOMPLETE`.
5. Publish a sanitized summary/review-request on PR #30 and share
   evidence with the independent reviewer via a **user-approved secure
   artifact location**. Do not commit secrets, browser profiles, private
   raw MCP logs or screenshot evidence to this repository.
6. Any failed hypothesis creates a narrowly scoped Design amendment
   proposal; no automatic promotion to production implementation.

## 6. Evidence bundle contract

Keep original evidence off-repo, e.g. private operator-approved directory
`<approved-evidence-root>/<run-id>/`; ensure permissions 0700 or
equivalent. Suggested contents:

~~~text
<run-id>/
  manifest.json
  inventory.json
  approvals.md                    # non-secret operator references
  commands.jsonl                  # command ID, host, UID, exit, UTC, sanitized stdout/stderr path
  cases.jsonl                     # task, BSL/FDR, expected, observed, verdict
  logs/                           # redacted and hashed, bounded excerpts
  artifacts/                      # test-only diagrams/outputs, no real private pages
  cleanup.json                    # owned units/pids/sockets/netns, disposition
  spike-0-report.md               # human-readable result and blocker decisions
~~~

Mandatory evidence fields per case:
`run_id`, `baseline_commit`, `requirements_blob`,
`design_blob`, `task_id`, `case_id`, `host`, `actor_uid`,
`command_id`, `expected`, `observed`, `exit_code`,
`started_at_utc`, `finished_at_utc`, `evidence_sha256`,
`test_environment` (mock | isolated-process | two-host-real),
`cleanup_state`, `verdict`, `blocking_reason`.

A printed “PASS” string without a matching command + observed negative
control + evidence hash is `NOT_PROVEN`. Preserve exact stdout/stderr only
after redaction and hash the **redacted, retained bytes**. Sensitive raw
logs stay off-repo with operator-controlled retention.

## 7. Human escalation template

When blocked by permissions or environmental assumptions, submit a
**bounded approval request** containing:

| Field | Required |
| --- | --- |
| Task/case and reason | SP0 ID, contract/BSL, why no nonprivileged substitute suffices |
| Target | Exact host, Unix account, unit/path/port/namespace; never guessed |
| Proposed commands | Exact commands or config diff; intended effective privileges |
| Risk | Which live services/logins/routes could be affected and rollback risks |
| Rollback | Exact reversal, state checks and cleanup owner |
| Validation | What PASS and failure evidence will look like |
| Time/lifetime | Test duration is operator-chosen; remove temporary privileges afterward |

The agent **must pause only that blocked task**, may continue independent
read-only tasks, and must not interpret silence as authorization.

## 8. Traceability matrix

| Design finding / contract | Spike verification |
| --- | --- |
| FDR-030-001, BSL-019 | SP0-05, SP0-06 stale Tunnel A vs Chrome B; revocation barrier |
| FDR-030-002, BSL-020 | SP0-03, SP0-06 unauthorized CDP TCP/UDS from both hosts |
| FDR-030-003, BSL-021 | SP0-05, SP0-09 tunnel-only loss, renew denial |
| FDR-030-004, BSL-022 | SP0-03, SP0-04 distinct UID and actual GUI seat |
| FDR-030-005, BSL-023 | SP0-04, SP0-09 independent Broker reaper/logout/restart |
| FDR-030-006, BSL-024 | SP0-09 evidence → release → report |
| FDR-030-007, BSL-025 | SP0-01, SP0-08 same registered MCP READY |
| FDR-030-008, BSL-027 | SP0-07 ordinary-netns app → Chrome-netns real HTTP |
| FDR-030-009, BSL-028 | SP0-02, SP0-05 sshd restrictions, forced stdio, Broker mapping |
| FDR-030-010, BSL-029 | SP0-03/04 separate Broker UID secrets/journal access denial |
| FDR-030-011, BSL-031 | SP0-01/08 B unauthorized on A's **same** MCP |
| FDR-030-012, BSL-032 | SP0-05/09 within-epoch N→N+1 transport fencing |
| FDR-030-013, BSL-033 | SP0-00/02/09 normative stdio + independent watchdog |
| BSL-001..018 and BSL-S01..S10 | SP0-00/03/08/09/10 plus coverage ledger |

**A single mock is never sufficient** for a finding requiring a real
OpenCode/SSH/Chrome/Ubuntu observation. Preserve both accepted and rejected
traces where security relies on denial.

## 9. Closure and transition authority

Possible overall outcomes:

- **SPIKE_PROVEN / AWAITING_INDEPENDENT_REVIEW**: all mandatory
  requirements backed by validated on-target evidence and cleanup
  completed; independent reviewer must still confirm before any
  implementation-plan authorization.
- **SPIKE_INCOMPLETE**: any NOT_RUN/INDETERMINATE or missing proof.
- **DESIGN_REVISION_REQUIRED**: reproducible violation of the approved
  design contract, return only that interface/requirement to Design.
- **BLOCKED_BY_OPERATOR_PREREQUISITE**: exact approvals/environment
  missing, no insecure workaround.
- **UNSAFE / STOPPED**: suspected breach or inability to constrain
  experiment; stop owned resources, preserve sanitized evidence and
  notify operator.

**No production implementation, deployment, merge or migration follows
automatically.** Require a separate reviewed implementation plan and
explicit human authorization.

## 10. AI agent handoff — copyable task instruction

~~~text
Repository: yohi/agent-skills
PR: #30 (Draft; do not merge)
Task: Execute the authorized Spike 0 verification plan in
docs/browser-session-lifecycle/spike-0-verification-plan.md.
Treat Requirements and Design blobs declared in that plan as immutable
review baselines. Begin with SP0-00 and SP0-01, preserving exact evidence.
Before modifying SSH, users, systemd, GUI state, network configuration,
permissions or rebooting either host, stop that step and obtain a
scoped human approval with exact commands and rollback.
Do not create production services, modify the Skill, merge PR #30,
reuse personal Chrome, expose CDP outside isolation, or loosen guards.
Run tasks in dependency order, distinguishing mock proof from actual
two-host evidence. Mark unavailable tasks BLOCKED/NOT_RUN and
continue only independent safe tasks. Produce sanitized evidence bundle,
requirement-by-requirement result and nonsecret PR summary, then request
independent review. Never self-authorize production implementation.
~~~

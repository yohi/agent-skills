# Agent-driven Setup — Spec 2: Capability and Verification Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, contract-driven capability assessment and target-specific verification while preserving the existing verification-plan stdout interface.

**Architecture:** `verify-setup.sh` is the sole orchestrator. It owns CLI parsing, path selection, temporary analysis, audit gates, capability assessment, report generation, dry-run admission, and exit codes. `run-target-probes.sh` is the only target-operation executor and returns one fixed JSON result for normal probe invocations; its separate side-effect-free `--classify-only` mode returns the shared safety classification. It is also the final safety enforcement owner immediately before process start. The enhanced path consumes Setup Contract v1 and PyYAML without installing dependencies or writing to the target during dry-run; the legacy simple path remains usable without PyYAML or Contract parsing.

**Tech Stack:** Bash 4+, Python 3, PyYAML `>=6.0,<7`, JSON, YAML frontmatter, Markdown.

## Global Constraints

- P0 and P1 only. Do not modify `evals/evals.json` or eval cases.
- Use the Setup Contract v1 schema, discovery protocol, CLI grammar, and error policy from the design without deviation.
- PyYAML is runtime-provisioned by the caller/CI for the enhanced path; enhanced-path scripts preflight it and never install it. The legacy simple path does not require PyYAML.
- `verify-setup.sh --dry-run` never writes to the target repository, including `.agent-setup`.
- `--report` paths and every temporary artifact are outside the target repository in dry-run.
- Capability availability and target verification result are separate report fields.
- Design の Probe Safety Policy v1 が command / Skill adapter の canonical registry、argv normalization、exact matching、fallback を所有する。`run-target-probes.sh` が分類実装の単一 owner であり、通常 verification は process start 直前に最終 gate を適用し、dry-run は `--classify-only` で同じ分類結果を取得する。MCP `initialize` / `tool_discovery` は固定 read-only protocol operation とする。
- Normal verification は実効 safety が `read_only` の command / Skill adapter と MCP `safety: read_only` representative call だけを実行する。MCP `temporary_fixture`、mutating、unknown、safety mismatch は通常 verification では `not_verified` / `safety_blocked`、dry-run では `not_executed` とし、P1 は外部 resource の operation と cleanup を自動実行しない。
- Only Contract-defined handoffs may be emitted.
- Preserve existing stdout JSON keys: `commands`, `notes`, and `makefile_targets`.

---

## File Structure

| File | Responsibility |
|---|---|
| `skills/agent-driven-setup/scripts/verify-setup.sh` | Orchestrator, CLI, dry-run plan, temporary cache, audit gate, assessment, report, exit code. |
| `skills/agent-driven-setup/scripts/run-target-probes.sh` | Sole executor of allowed target probes, shared safety classifier, and P1 unsupported temporary-fixture rejection. |
| `skills/agent-driven-setup/scripts/test-scripts.sh` | Regression fixtures for all behavior-changing paths. |
| `skills/agent-driven-setup/references/setup-capability-matrix.md` | Capability definitions and P1 profile boundaries. |
| `skills/agent-driven-setup/references/agent-capability-matrix.md` | Generic prerequisite cross-reference only. |
| `skills/agent-driven-setup/references/verification-patterns.md` | Normative user-facing dry-run, report, and handoff guidance. |
| `skills/agent-driven-setup/references/agent-protocol-template.md` | Generated protocol wording for report and handoff lifecycle. |
| `skills/agent-driven-setup/references/human-entry-point-template.md` | Human-facing separation of implementation and verification completion. |
| `skills/agent-driven-setup/SKILL.md` | Workflow instructions that invoke the fixed components. |

---

### Task 1: Publish the capability and verification references

**Files:**
- Create: `skills/agent-driven-setup/references/setup-capability-matrix.md`
- Modify: `skills/agent-driven-setup/references/agent-capability-matrix.md`
- Modify: `skills/agent-driven-setup/references/verification-patterns.md`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Spec 1 Tasks 1 through 3.

**Consumes:** Setup Contract v1 `required_capabilities`, probe discriminators, mutation surfaces, and P0/P1 scope.

**Produces:** capability vocabulary, target default profiles, and documentation-only verification rules.

**Interfaces:** capability status is exactly `available`, `unavailable`, or `unknown`; Spec 2 resolves each Contract capability ID against `setup-capability-matrix.md`, with a missing definition reported as `unknown` and its dependent item as `not_verified`; P1 supports MCP stdio `read_only` representative calls, Contract-adapter Skill agent actions whose effective safety is `read_only`, and read-only CLI/Service commands whose effective safety is `read_only`; MCP `temporary_fixture` is accepted by the Contract shape but unsupported for automatic P1 execution; Plugin, Hook, and `other/custom` return Contract-defined handoff without invented probes. Safety-blocked items are `not_verified` and use `error_category: safety_blocked`.

**RED:**
- [ ] Add documentation assertions for `mcp_runtime_probe`, `agent_discovery_probe`, `representative_activation_probe`, `available | unavailable | unknown`, missing matrix definitions, target-operation separation, the distinction between declared and effective safety, and `unknown → not_verified` / `safety_blocked`.
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh`.
- [ ] Confirm the assertions fail before the reference material exists.

**GREEN:**
- [ ] Define every setup-specific capability with `description`, `generic_prerequisites.candidates`, and the rule that prerequisites do not derive availability.
- [ ] Add the P1 target profiles and exact dry-run/report/handoff rules.
- [ ] Run the suite and confirm the documentation assertions pass.

**REFACTOR:**
- [ ] Remove duplicated capability descriptions without changing the canonical matrix; rerun the suite.

**Commit:**
- [ ] Stage only the three reference documents and `test-scripts.sh`.
- [ ] Commit: `docs: setup検証capability matrixを追加`.

### Task 2: Add CLI parsing, dependency preflight, and dry-run I/O safety

**Files:**
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Spec 1 Tasks 1 and 2; Task 1.

**Consumes:** `verify-setup.sh [--dry-run] [--contract <repo-relative-path>] [--report <target-external-markdown-path>] <repo-path>`, the PyYAML-free legacy/enhanced path-selection gate, Setup Contract discovery, Probe Safety Policy v1 and its `run-target-probes.sh --classify-only` interface, and mutation-surface semantics.

**Produces:** additive dry-run object with `dry_run.decision: execute|not_executed`, external temporary cache, before/after snapshot, explicit target-probe safety decisions obtained from the shared classifier, and exit codes 1 through 3.

**Interfaces:** normal `category` remains `safe|review`; dry-run never uses `safe` or `review` as its decision; CLI parsing and simple-path selection do not require PyYAML; the legacy path is selected when there is no trigger or Contract indicator; the enhanced path preflights PyYAML before canonical Contract discovery or any target write; dry-run invokes `run-target-probes.sh --classify-only` for each command/adapter argv, classifies effective `read_only` as `execute` and `temporary_fixture`, `mutating`, `unknown`, or safety mismatch as `not_executed` before target process start; malformed grammar/Contract is exit 2 and missing enhanced-path PyYAML is exit 3 with no install attempt.

**RED:**
- [ ] Add a pristine Git fixture without `.agent-setup`; invoke `verify-setup.sh --dry-run <repo>` and assert `test ! -e "$repo/.agent-setup"` and empty `git -C "$repo" status --porcelain`.
- [ ] Add fixtures asserting the Policy v1 entries `node --version` and `git status --porcelain` are `dry_run.decision == "execute"`, while `npm install`, a Contract-declared MCP `temporary_fixture`, and `unknown-command --check` are `"not_executed"` without target process start.
- [ ] Add a target-internal `--report` fixture and a missing-PyYAML PATH fixture.
- [ ] Add a no-trigger/no-Contract simple-repository fixture with a PATH lacking importable PyYAML; assert the legacy JSON plan succeeds without a dependency handoff. In the same RED setup, add an enhanced Contract fixture and assert that the same missing dependency returns exit 3 without an install attempt.
- [ ] Run the suite and confirm failure because the current script writes `.agent-setup` before classification and has no new grammar.

**GREEN:**
- [ ] Parse all options before one required repository path and preserve default stdout JSON.
- [ ] Parse CLI and perform the read-only, PyYAML-free path-selection gate first. Keep the no-trigger/no-Contract simple path on the existing workflow without PyYAML; only after enhanced path selection preflight PyYAML, discover/read the Contract, create target-external temporary storage, and take the before snapshot before any target write. Ask `run-target-probes.sh --classify-only` for every command/adapter admission and apply the shared classification before invoking any target probe.
- [ ] In dry-run, analyze through the external temporary cache; never create or update the target `.agent-setup` cache.
- [ ] Use only the Policy v1 classifier result: effective known read-only commands/adapters with matching declarations are `execute`; temporary fixtures, mutating, unknown, and mismatched commands/adapters are `not_executed` without target process start; emit invariant violation and exit 1 on an unexpected local mutation, snapshot failure, or temporary-storage cleanup failure.
- [ ] Reject target-internal report paths in dry-run and emit exit 2; report missing PyYAML as exit 3 with an explicit provisioning handoff only for the enhanced path, while preserving simple-path success without PyYAML.
- [ ] Run the suite and confirm every added fixture passes.

**REFACTOR:**
- [ ] Centralize target-external path validation if report, cache, evidence, and snapshot checks duplicate it; rerun the suite.

**Commit:**
- [ ] Stage only `verify-setup.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: dry-runのI/O不変条件を保証`.

### Task 3: Add fixed Verification Report generation and audit gates

**Files:**
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Spec 1 Task 3; Task 2.

**Consumes:** Audit Report `affected_target_ids`, Contract `verification.targets`, `required_for_e2e`, `handoffs`, and `--report`.

**Produces:** Markdown Verification Report at `--report`, additive `verification_report` data in stdout JSON, and deterministic exit 0 or 4.

**Interfaces:** default stdout remains the legacy plan JSON; report contains `generated_at`, targets/items, capability assessment, handoff execution records, dry-run result, and `overall_status`; `confirmed`/`candidate`/`unresolved` never directly overwrite item status; a normal safety rejection is recorded as item `status: not_verified` with `error_category: safety_blocked`, while a dry-run suppression is recorded only as `dry_run.decision: not_executed`.

**RED:**
- [ ] Add fixtures for all required items verified, one runtime failure, a confirmed affected audit finding, an unresolved affected finding, and an unaffected second target.
- [ ] Run the suite and confirm failure because no report path exists, E2E status is absent, and audit findings are not target-scoped.

**GREEN:**
- [ ] Render the report only to `--report`; keep stdout JSON parseable and backward-compatible.
- [ ] Derive `not_applicable`, `verified`, and `not_verified` exclusively from required item statuses.
- [ ] Block probes for schema errors or affected `confirmed` findings, record `audit_blocked`, and exit 4.
- [ ] Permit unaffected targets to continue; keep candidate/unresolved findings as review records but force only the affected target's E2E sign-off to `not_verified` until resolved.
- [ ] Run the suite and confirm report shape, stdout keys, target isolation, and exit status.

**REFACTOR:**
- [ ] Extract report serialization only if stdout and Markdown report disagree on an item status; rerun the suite.

**Commit:**
- [ ] Stage only `verify-setup.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: 監査ゲート付きVerification Reportを生成`.

### Task 4: Implement capability assessment in the orchestrator

**Files:**
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Tasks 1 through 3.

**Consumes:** Contract `required_capabilities`, capability matrix definitions, and audit gate results.

**Produces:** `capability_assessment.<capability> = {status, reason, evidence}` and per-item decision data.

**Interfaces:** only `verify-setup.sh` owns assessment; matrix lookup occurs in Spec 2 and an undefined setup capability is `unknown`; an available capability plus target failure remains `available`; unavailable/unknown capability yields `not_verified` and only its referenced `handoff_id` may be emitted.

**RED:**
- [ ] Add fixtures for an undefined setup capability, unavailable `mcp_runtime_probe`, unknown Skill activation capability, available MCP runtime with initialize failure, and an item without `handoff_id`.
- [ ] Run the suite and confirm failure because assessment and target result are not separate fields.

**GREEN:**
- [ ] Implement concrete, non-mutating environment/observability checks for each P1 capability.
- [ ] Record one of the three exact statuses with evidence and reason.
- [ ] Mark dependent items `not_verified` on unavailable or unknown capability; omit a handoff when the Contract has none.
- [ ] Preserve `available` when the later target probe fails.
- [ ] Run the suite and confirm the four result combinations and exit 4 behavior.

**REFACTOR:**
- [ ] Normalize repeated capability-result construction without hiding capability-specific evidence; rerun the suite.

**Commit:**
- [ ] Stage only `verify-setup.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: setup capability評価を追加`.

### Task 5: Implement the target-specific probe executor

**Files:**
- Create: `skills/agent-driven-setup/scripts/run-target-probes.sh`
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Tasks 2 through 4.

**Consumes:** `run-target-probes.sh --contract <path> --target <target-id> --item <verification-item-id> --evidence-dir <external-temp-dir>`, its side-effect-free `--classify-only` interface, Design の Probe Safety Policy v1, and Contract `probe` definitions, including explicit MCP arguments/safety, required command/adapter safety declarations, and Skill adapter definitions.

**Produces:** one JSON object `{target_id, item_id, status, reason, evidence, error_category}` per invocation.

**Interfaces:** `--item` selects one target-local verification item; the executor derives phase from that item and never selects by phase alone. `--classify-only` reads one JSON object from stdin, `{"argv":[...],"declared_safety":"read_only|mutating|unknown"}`, and emits one JSON object, `{"effective_safety":"read_only|mutating|unknown","declaration_matches":true|false}`, without reading or writing a target or starting a target operation. Executor exclusively owns the registry, classifier, process lifecycle, timeout, target operation execution, and final safety enforcement immediately before process start. The Policy v1 registry is exactly `["node", "--version"]` and `["git", "status", "--porcelain"]` as `read_only`, and `["npm", "install"]` as `mutating`; matching is full argv exact match with no path normalization, wrapper unwrapping, or trailing arguments, and every other argv is `unknown`. A declaration is not execution permission, and a declaration/effective-class mismatch is safety-blocked. Normal verification executes only effective `read_only` probes and MCP `representative_tool_call` with `safety: read_only`. Contract-defined MCP `temporary_fixture` is schema-valid but unsupported for automatic P1 execution: normal verification returns `not_verified` / `safety_blocked` before operation or cleanup, while dry-run returns `not_executed`. Dry-run invokes the same `--classify-only` classifier used by the normal executor and differs only in execution decision. MCP representative calls use Contract-provided `tool`, JSON-object `arguments`, and `safety`; Skill `agent_action` uses Contract-provided public adapter `argv` and prompt stdin only after the safety gate. Adapter exit 0 plus observable response is `verified`, unavailable mechanism is `capability_unavailable`, non-zero exit is `runtime_failure`, and a normal safety rejection or unsupported probe mode is `not_verified` / `safety_blocked`; status is `verified|not_verified|not_applicable`; error category is `null|capability_unavailable|runtime_failure|audit_blocked|safety_blocked`.

`cleanup_required: true` does not permit a Contract-provided cleanup command. P1 does not define or invoke a transport, snapshot method, or cleanup path for `temporary_fixture`; the executor blocks before operation start as `unsupported probe mode` / `safety_blocked`, and emits only a Contract-defined handoff when one exists.

**RED:**
- [ ] Add an MCP stdio fixture that answers initialize and tools/list, a fixture whose initialize returns an error, and a safe `read_only` representative tool fixture with explicit `tool`, `arguments`, and `safety`; add an unsupported `temporary_fixture` fixture with an external `snapshot: required` / `cleanup_required: true` mutation-surface reference and an optional Contract-defined handoff; add a Skill discovery/activation fixture with an explicit public adapter and separate unsafe/unknown-safety adapter fixtures; add the named Policy v1 command fixtures `node --version`, `git status --porcelain`, `npm install`, and `unknown-command --check`, plus absolute-path and wrapper variants that must remain `unknown`; add a Plugin fixture with only a handoff.
- [ ] Assert that normal known-mutating/unknown commands and unsafe/unknown/mismatched adapters do not start a target process and return `status: not_verified` with `error_category: safety_blocked`; for each same-argv normal/dry-run pair, assert identical `effective_safety` and `declaration_matches`, then assert normal rejection versus dry-run `dry_run.decision: not_executed`.
- [ ] Assert that a normal Contract-defined MCP `temporary_fixture` is blocked before the representative operation and any cleanup starts with `status: not_verified` / `error_category: safety_blocked`, that its defined handoff is the only handoff emitted, and that dry-run returns `dry_run.decision: not_executed` without starting the temporary operation.
- [ ] Run the suite and confirm failure because the executor does not exist and no probe JSON can be parsed.

**GREEN:**
- [ ] Implement P1 MCP stdio JSON-RPC `initialize`, `tool_discovery`, and the Contract-selected `safety: read_only` representative tool call using its explicit `tool`, `arguments`, and safety, with timeout and termination. Reject Contract-defined `temporary_fixture` before the representative operation in normal verification as `not_verified` / `safety_blocked`, emit only its defined handoff, and never invoke it in dry-run.
- [ ] Implement Skill `agent_action` discovery/activation by executing the Contract-provided public adapter `argv` without a shell and passing `prompt` through its declared stdin mode. Apply the effective safety gate before process start; return `not_verified` / `safety_blocked` for unsafe, unknown, or mismatched adapters, and return `not_verified` when the adapter or capability is unavailable.
- [ ] Implement CLI/Service `command` probes only when the effective safety is `read_only`; return `not_verified` / `safety_blocked` for known-mutating, unknown, or mismatched command declarations, and never treat the normal plan's `category` as target-probe authorization.
- [ ] For Plugin, Hook, and `other/custom`, return `not_verified` with only a Contract-defined handoff; never invent a command or operation.
- [ ] On normal unsupported `temporary_fixture` mode return `not_verified` / `safety_blocked` before any external operation or cleanup; on target operation error return `not_verified` / `runtime_failure` without changing capability availability. In dry-run, temporary, mutating, mismatched, and unknown operations are `not_executed`, while an unexpected local mutation or temporary-storage cleanup failure is `dry_run_invariant_violation` with exit 1.
- [ ] Run the suite and confirm every fixture emits one valid JSON result and leaves target fixtures unchanged.

**REFACTOR:**
- [ ] Extract transport-independent JSON result rendering if all probe types duplicate it; rerun the suite.

**Commit:**
- [ ] Stage only `run-target-probes.sh`, `verify-setup.sh`, and `test-scripts.sh`.
- [ ] Commit: `feat: target別E2E probe executorを追加`.

### Task 6: Update protocol, entry point, and skill workflow

**Files:**
- Modify: `skills/agent-driven-setup/references/agent-protocol-template.md`
- Modify: `skills/agent-driven-setup/references/human-entry-point-template.md`
- Modify: `skills/agent-driven-setup/SKILL.md`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Tasks 1 through 5.

**Consumes:** fixed orchestrator CLI, report schema, P1 support boundaries, and handoff semantics.

**Produces:** documentation-only instructions that invoke exact components and report verified versus not-verified states.

**Interfaces:** Contract defines handoff; report records execution; Agent does not construct an undefined handoff; `blocked_by` skips dependent probes; a normal `safety_blocked` item emits only its Contract-defined handoff as pending/needs_review, while a dry-run `not_executed` decision does not create a target runtime failure.

**RED:**
- [ ] Add documentation assertions for the fixed `verify-setup.sh` grammar, report destination, audit gate, capability/target distinction, and handoff applicability condition.
- [ ] Run the suite and confirm these assertions fail before updates.

**GREEN:**
- [ ] Add the fixed workflow order: audit gate, capability assessment, dependency-aware probe execution, report, handoff.
- [ ] Document the fixed safety order: Contract declaration, Policy v1 classification through the executor (normal final gate or dry-run `--classify-only`), process-start enforcement, and deterministic `safety_blocked` / `not_executed` result mapping.
- [ ] State that implementation completion is distinct from verification completion and that unresolved affected audit findings prevent E2E sign-off.
- [ ] Run the suite and confirm documentation assertions pass.

**REFACTOR:**
- [ ] Remove overlapping wording while retaining one canonical contract reference; rerun the suite.

**Commit:**
- [ ] Stage only the three documentation files and `test-scripts.sh`.
- [ ] Commit: `docs: verification実行とhandoff手順を同期`.

### Task 7: Verify Spec 2 integration readiness

**Files:**
- Create: none
- Modify: none
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`, `scripts/validate-skills.js`

**Depends on:** Tasks 1 through 6.

**Consumes:** all Spec 2 deliverables and the recorded implementation baseline SHA.

**Produces:** integration-checkpoint evidence, not new implementation.

**Interfaces:** validate the committed delta with `git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD` against the complete permitted Issue #12 P0/P1 implementation-path set, and validate the dirty state with `git status --short` separately. Do not interpret the shared baseline diff as a Spec 2-only delta.

**RED:**
- [ ] Not applicable: this is a read-only verification task.

**GREEN:**
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh` and confirm success.
- [ ] Run `node scripts/validate-skills.js` and confirm 0 errors and 0 warnings.
- [ ] Run the baseline diff and confirm every changed path is within the permitted Issue #12 P0/P1 implementation paths, including the already-completed Spec 1 paths; separately confirm no eval path changed.
- [ ] Run the Integration Checkpoint `is_allowed_implementation_path` guard against committed, staged, unstaged, and untracked paths; confirm it exits 0.

**REFACTOR:**
- [ ] Not applicable.

**Commit:**
- [ ] Do not create an empty commit; commit only required correction files with `fix: Spec 2統合検証の指摘を修正`.

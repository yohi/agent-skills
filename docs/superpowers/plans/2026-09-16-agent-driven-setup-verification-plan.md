# Agent-driven Setup — Spec 2: Capability and Verification Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, contract-driven capability assessment and target-specific verification while preserving the existing verification-plan stdout interface.

**Architecture:** `verify-setup.sh` is the sole orchestrator. It owns CLI parsing, temporary analysis, audit gates, capability assessment, report generation, and exit codes. `run-target-probes.sh` is the only target-operation executor and returns one fixed JSON result. Both consume Setup Contract v1 and PyYAML without installing dependencies or writing to the target during dry-run.

**Tech Stack:** Bash 4+, Python 3, PyYAML `>=6.0,<7`, JSON, YAML frontmatter, Markdown.

## Global Constraints

- P0 and P1 only. Do not modify `evals/evals.json` or eval cases.
- Use the Setup Contract v1 schema, discovery protocol, CLI grammar, and error policy from the design without deviation.
- PyYAML is runtime-provisioned by the caller/CI; scripts preflight it and never install it.
- `verify-setup.sh --dry-run` never writes to the target repository, including `.agent-setup`.
- `--report` paths and every temporary artifact are outside the target repository in dry-run.
- Capability availability and target verification result are separate report fields.
- Only Contract-defined handoffs may be emitted.
- Preserve existing stdout JSON keys: `commands`, `notes`, and `makefile_targets`.

---

## File Structure

| File | Responsibility |
|---|---|
| `skills/agent-driven-setup/scripts/verify-setup.sh` | Orchestrator, CLI, dry-run plan, temporary cache, audit gate, assessment, report, exit code. |
| `skills/agent-driven-setup/scripts/run-target-probes.sh` | Sole executor of allowed target probes and their cleanup. |
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

**Interfaces:** capability status is exactly `available`, `unavailable`, or `unknown`; P1 supports MCP stdio, Skill agent actions, and read-only CLI/Service commands; Plugin, Hook, and `other/custom` return Contract-defined handoff without invented probes.

**RED:**
- [ ] Add documentation assertions for `mcp_runtime_probe`, `agent_discovery_probe`, `representative_activation_probe`, `available | unavailable | unknown`, target-operation separation, and `unknown → not_verified`.
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

**Consumes:** `verify-setup.sh [--dry-run] [--contract <repo-relative-path>] [--report <target-external-markdown-path>] <repo-path>`, Setup Contract discovery, and mutation-surface semantics.

**Produces:** additive dry-run object with `dry_run.decision: execute|not_executed`, external temporary cache, before/after snapshot, and exit codes 1 through 3.

**Interfaces:** normal `category` remains `safe|review`; dry-run never uses `safe` or `review` as its decision; malformed grammar/Contract is exit 2 and missing PyYAML is exit 3 with no install attempt.

**RED:**
- [ ] Add a pristine Git fixture without `.agent-setup`; invoke `verify-setup.sh --dry-run <repo>` and assert `test ! -e "$repo/.agent-setup"` and empty `git -C "$repo" status --porcelain`.
- [ ] Add fixtures asserting `node --version` and `git status --porcelain` are `dry_run.decision == "execute"`, while `npm install` and `unknown-command --check` are `"not_executed"`.
- [ ] Add a target-internal `--report` fixture and a missing-PyYAML PATH fixture.
- [ ] Run the suite and confirm failure because the current script writes `.agent-setup` before classification and has no new grammar.

**GREEN:**
- [ ] Parse all options before one required repository path and preserve default stdout JSON.
- [ ] Before any target write, preflight PyYAML, discover/read the Contract, create target-external temporary storage, and take the before snapshot.
- [ ] In dry-run, analyze through the external temporary cache; never create or update the target `.agent-setup` cache.
- [ ] Classify only known read-only commands as `execute`; suppress mutating and unknown commands as `not_executed`; emit invariant violation and exit 1 on snapshot or cleanup failure.
- [ ] Reject target-internal report paths in dry-run and emit exit 2; report missing PyYAML as exit 3 with an explicit provisioning handoff.
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

**Interfaces:** default stdout remains the legacy plan JSON; report contains `generated_at`, targets/items, capability assessment, handoff execution records, dry-run result, and `overall_status`; `confirmed`/`candidate`/`unresolved` never directly overwrite item status.

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

**Interfaces:** only `verify-setup.sh` owns assessment; an available capability plus target failure remains `available`; unavailable/unknown capability yields `not_verified` and only its referenced `handoff_id` may be emitted.

**RED:**
- [ ] Add fixtures for unavailable `mcp_runtime_probe`, unknown Skill activation capability, available MCP runtime with initialize failure, and an item without `handoff_id`.
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

**Consumes:** `run-target-probes.sh --contract <path> --target <target-id> --phase <phase> --evidence-dir <external-temp-dir>` and Contract `probe` definitions.

**Produces:** one JSON object `{target_id, item_id, status, reason, evidence, error_category}` per invocation.

**Interfaces:** executor exclusively owns process lifecycle, timeout, temporary fixture cleanup, and target operation execution; status is `verified|not_verified|not_applicable`; error category is `null|capability_unavailable|runtime_failure|audit_blocked|safety_blocked`.

**RED:**
- [ ] Add an MCP stdio fixture that answers initialize and tools/list, a fixture whose initialize returns an error, a safe representative tool fixture, a Skill discovery fixture, a CLI read-only command fixture, and a Plugin fixture with only a handoff.
- [ ] Run the suite and confirm failure because the executor does not exist and no probe JSON can be parsed.

**GREEN:**
- [ ] Implement P1 MCP stdio JSON-RPC `initialize`, `tool_discovery`, and Contract-selected safe representative tool call with timeout and termination.
- [ ] Implement Skill `agent_action` discovery/activation only through observable agent mechanisms; return `not_verified` when unavailable.
- [ ] Implement read-only `command` probes for CLI/Service.
- [ ] For Plugin, Hook, and `other/custom`, return `not_verified` with only a Contract-defined handoff; never invent a command or operation.
- [ ] On cleanup failure return `safety_blocked`; on target operation error return `runtime_failure` without changing capability availability.
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

**Interfaces:** Contract defines handoff; report records execution; Agent does not construct an undefined handoff; `blocked_by` skips dependent probes.

**RED:**
- [ ] Add documentation assertions for the fixed `verify-setup.sh` grammar, report destination, audit gate, capability/target distinction, and handoff applicability condition.
- [ ] Run the suite and confirm these assertions fail before updates.

**GREEN:**
- [ ] Add the fixed workflow order: audit gate, capability assessment, dependency-aware probe execution, report, handoff.
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

**Interfaces:** validate the committed delta with `git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD` and the dirty state with `git status --short` separately.

**RED:**
- [ ] Not applicable: this is a read-only verification task.

**GREEN:**
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh` and confirm success.
- [ ] Run `node scripts/validate-skills.js` and confirm 0 errors and 0 warnings.
- [ ] Run the baseline diff and confirm only the intended Spec 2 paths changed; separately confirm no eval path changed.

**REFACTOR:**
- [ ] Not applicable.

**Commit:**
- [ ] Do not create an empty commit; commit only required correction files with `fix: Spec 2統合検証の指摘を修正`.

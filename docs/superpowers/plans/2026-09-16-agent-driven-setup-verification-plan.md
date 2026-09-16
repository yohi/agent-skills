# Agent-driven Setup — Spec 2: Capability & Verification Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `skills/agent-driven-setup/` with setup-specific capability matrix, target-specific E2E verification, dry-run safety classifier, scoped snapshot, and handoff/evidence lifecycle.

**Architecture:** A new `setup-capability-matrix.md` defines setup-specific capabilities as layers above generic capabilities. `verify-setup.sh` is extended with a dry-run mode that only executes known-safe operations and compares before/after snapshots of expected mutation surfaces. Verification reports record per-item status, capability assessment, and handoff execution without collapsing handoff completion into verification success.

**Tech Stack:** Bash, Python 3 with PyYAML (shared Setup Contract parsing dependency), Markdown, YAML frontmatter.

## Global Constraints

- P0 + P1 only; P2 eval suite expansion is out of scope.
- `setup-capability-matrix.md` must not redefine generic capability availability; it references `agent-capability-matrix.md` as a prerequisite source.
- Dry-run must not mutate persistent state in repository, user settings, system/global config, Agent Skill directory, Plugin registry, or external services.
- Unknown side-effect commands are `not_executed` during dry-run, never executed speculatively.
- Handoff completion does not automatically mark a verification item as `verified`; evidence must be evaluated against `required_evidence`.
- E2E status is derived from individual verification items (`required_for_e2e`), not a separate truth.
- No absolute paths specific to a user or machine may be committed.

---

## File Structure

| File | Responsibility |
|---|---|
| `skills/agent-driven-setup/references/setup-capability-matrix.md` | Defines setup-specific capabilities, generic-prerequisite candidates, and target-type default profiles. |
| `skills/agent-driven-setup/references/agent-capability-matrix.md` | Adds prerequisite mapping from setup-specific capabilities; keeps generic availability as source of truth. |
| `skills/agent-driven-setup/references/verification-patterns.md` | Adds target-specific verification, dry-run invariant, and handoff/evidence lifecycle sections. |
| `skills/agent-driven-setup/references/agent-protocol-template.md` | Adds verification phase and handoff pattern language to generated protocols. |
| `skills/agent-driven-setup/references/human-entry-point-template.md` | Adds E2E verified/unverified reporting language to README paste prompt guidance. |
| `skills/agent-driven-setup/scripts/verify-setup.sh` | Adds `--dry-run` mode, conservative command classifier, scoped before/after snapshot, dry-run invariant violation report. |
| `skills/agent-driven-setup/scripts/test-scripts.sh` | Adds tests for dry-run classifier, snapshot behavior, and verification report shape. |
| `skills/agent-driven-setup/SKILL.md` | Adds verification execution, handoff, and reporting sections. |

---

### Task 1: Create `setup-capability-matrix.md` reference

**Files:**
- Create: `skills/agent-driven-setup/references/setup-capability-matrix.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: reference document with capability definitions and default profiles.
- Consumes: generic capability names from `agent-capability-matrix.md`.

- [ ] **Step 1: Write capability definitions**

Create `skills/agent-driven-setup/references/setup-capability-matrix.md` with setup-specific capabilities:

- `target_installation`
- `target_registration`
- `agent_discovery_probe`
- `representative_activation_probe`
- `mcp_runtime_probe`
- `mcp_client_registration`
- `client_reload_new_session`
- `hook_registration`
- `external_health_check`
- `artifact_secret_lifecycle`

For each capability:
- `description`
- `generic_prerequisites.candidates` (list, not AND condition)
- `note` clarifying that availability is determined by concrete probe, not prerequisite AND

- [ ] **Step 2: Write default profiles**

For target types `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, `other/custom`, list `commonly_used` capabilities. Do not use `required`/`optional`; these are hints only. Final requirement comes from Setup Contract.

- [ ] **Step 3: Add a test verifying frontmatter parseability**

If the document contains an example frontmatter block, parse it and assert `setup_capability_matrix_version` is present.

- [ ] **Step 4: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/agent-driven-setup/references/setup-capability-matrix.md
git commit -m "docs: add setup-specific capability matrix reference"
```

---

### Task 2: Update `agent-capability-matrix.md` with prerequisite mapping

**Files:**
- Modify: `skills/agent-driven-setup/references/agent-capability-matrix.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: updated matrix that references setup-specific capabilities but does not redefine their availability.

- [ ] **Step 1: Add a "Setup-specific capabilities that depend on these" section**

Append a section listing, for each generic capability, which setup-specific capabilities typically use it as a prerequisite candidate. Keep generic capability definitions and platform mapping unchanged.

- [ ] **Step 2: Add test**

Test that the new section header exists.

- [ ] **Step 3: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add skills/agent-driven-setup/references/agent-capability-matrix.md
git commit -m "docs: link generic capabilities to setup-specific prerequisites"
```

---

### Task 3: Update `verification-patterns.md`

**Files:**
- Modify: `skills/agent-driven-setup/references/verification-patterns.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: extended verification patterns covering target-specific E2E, dry-run invariant, and handoff lifecycle.

- [ ] **Step 1: Add target-specific E2E section**

Document conceptual chains:
- Skill: install/register → agent discovery → representative activation
- MCP: runtime start → initialize → tool discovery → representative tool call
- Plugin/Hook/CLI/Service: generic chain from Setup Contract

Representative operation must be safe, read-only where possible, and selected from Setup Contract.

- [ ] **Step 2: Add dry-run invariant section**

Document:
- 3-layer defense: policy, classifier, snapshot.
- `unknown → not_executed` rule.
- ephemeral operation requirements: pre-defined cleanup + mutation surface + post-execution snapshot.
- snapshot targets derived from Setup Contract `external_effects.mutation_surfaces`.

- [ ] **Step 3: Add handoff/evidence lifecycle section**

Document:
- Contract defines handoff; Verification Report records execution.
- handoff completed → evidence acquired → evaluate against `required_evidence` → `evaluation_result` → item status.
- evidence is summary/reference, not full transcript.
- secret-bearing evidence handled by `artifact_secret_lifecycle`.

- [ ] **Step 4: Add test**

Verify new section headers exist.

- [ ] **Step 5: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/agent-driven-setup/references/verification-patterns.md
git commit -m "docs: add target-specific E2E, dry-run, and handoff verification patterns"
```

---

### Task 4: Update `agent-protocol-template.md`

**Files:**
- Modify: `skills/agent-driven-setup/references/agent-protocol-template.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: template that includes target-specific verification phase and handoff patterns.

- [ ] **Step 1: Extend required elements**

Add:
- Representative operation / smoke test description.
- Handoff pattern for steps the agent cannot autonomously complete.
- Capability contract may include setup-specific capabilities when the repository is complex.

- [ ] **Step 2: Update minimal protocol section**

Add optional sentences for verification and handoff in the template snippet.

- [ ] **Step 3: Add test**

Verify updated elements are present.

- [ ] **Step 4: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/agent-driven-setup/references/agent-protocol-template.md
git commit -m "docs: extend agent protocol template for target-specific verification"
```

---

### Task 5: Update `human-entry-point-template.md`

**Files:**
- Modify: `skills/agent-driven-setup/references/human-entry-point-template.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: template guidance that includes E2E status reporting.

- [ ] **Step 1: Add E2E reporting note**

Add guidance that the final report must distinguish implementation completion from verification completion and list unverified items with handoff instructions.

- [ ] **Step 2: Add test**

Verify the note exists.

- [ ] **Step 3: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add skills/agent-driven-setup/references/human-entry-point-template.md
git commit -m "docs: add E2E status reporting guidance to human entry point template"
```

---

### Task 6: Extend `verify-setup.sh` with dry-run classifier and scoped snapshot

**Files:**
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Consumes: `--dry-run` flag, existing `analyze.json`, optional Setup Contract.
- Produces: verification plan with `safe`/`review`/`not_executed` categories; dry-run invariant report.

- [ ] **Step 1: Add `--dry-run` argument parsing**

Add `--dry-run` boolean flag. When set, change classifier behavior.

- [ ] **Step 2: Implement dry-run command classifier**

In dry-run mode:
- `read-only` / known-safe → `execute`
- known-mutating (install, publish, apply, deploy, push, etc.) → `not_executed`
- unknown → `not_executed`

Normal mode retains existing `safe`/`review` categories.

`not_executed` entries include `reason`.

- [ ] **Step 3: Implement scoped snapshot**

When `--dry-run` is set:
1. Compute expected mutation surfaces from Setup Contract `external_effects.mutation_surfaces`. If the contract is absent, use only the repository working tree and any surfaces explicitly declared by repository evidence (`AGENTS.md`, CI, installer docs).
2. Do not add blanket default snapshots of `$HOME/.claude/`, `$HOME/.opencode/`, or other Agent-global directories unless explicitly named by the contract or repository evidence.
3. Record metadata (path, mtime, size, hash) into a temporary directory.
4. Execute only `execute` classified commands.
5. Record after snapshot.
6. Compare and report `dry_run_invariant_violation` if unexpected mutations exist.
7. Clean up temporary snapshot directory.

Do not snapshot the whole home directory; use concrete surfaces only.

- [ ] **Step 4: Emit dry-run invariant report**

Add to verification plan JSON:

```json
{
  "dry_run": {
    "enabled": true,
    "snapshot_status": "clean | violation",
    "violations": []
  }
}
```

- [ ] **Step 5: Add tests**

Create fixtures and assert:
1. `node --version` is `execute` in dry-run.
2. `git status --porcelain` is `execute` in dry-run.
3. `npm install` is `not_executed` in dry-run.
4. Unknown command is `not_executed` in dry-run.
5. Repository test commands (e.g., `npm test`) are only `execute` when repository evidence explicitly marks them read-only or they are covered by a safe allowlist; otherwise `review` in normal mode and `not_executed` in dry-run.
6. A read-only / pre-approved ephemeral test operation that is classified as safe but unexpectedly mutates a tracked file is detected by snapshot comparison and reported as `dry_run_invariant_violation`.
- [ ] **Step 6: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/agent-driven-setup/scripts/verify-setup.sh
git commit -m "feat: add dry-run classifier and scoped snapshot to verify-setup.sh"
```

---

### Task 7: Verification report generation

**Files:**
- Create or extend a verification report helper in `skills/agent-driven-setup/scripts/verify-setup.sh` or a small companion script.
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Consumes: Setup Contract `verification` definition, capability assessment, handoff records.
- Produces: Verification Report YAML frontmatter + Markdown.

- [ ] **Step 1: Define verification report schema**

Use schema version `verification_report_schema_version: 1`.

Fields:
- `generated_at`
- `targets[*].target_type`
- `targets[*].e2e_status` + `e2e_status_reason`
- `targets[*].items[*].id`, `status`, `reason`, `handoff_id`, `next_step`, `required_evidence`
- `capability_assessment` map with `status: available | unavailable | unknown`, `reason`, `evidence`
- `handoffs` execution records with `status`, `evaluation_result`, `evidence`

- [ ] **Step 2: Implement report generation in verify-setup.sh**

After executing safe verification steps and assessing capabilities, generate the report to stdout or a path specified by `--report <path>`.

- [ ] **Step 3: Implement E2E status derivation**

Algorithm:
1. For each target, collect items where `required_for_e2e` is true and status is not `not_applicable`.
2. If none, `e2e_status = not_applicable`.
3. If all are `verified`, `e2e_status = verified`.
4. Otherwise, `e2e_status = not_verified` with reason listing unverified required items.

- [ ] **Step 4: Add tests**

Test fixtures with:
1. All required items verified → `e2e_status: verified`.
2. One required item not_verified → `e2e_status: not_verified`.
3. Only optional items → `e2e_status: not_applicable`.

- [ ] **Step 5: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/agent-driven-setup/scripts/verify-setup.sh
git commit -m "feat: generate verification report with E2E status derivation"
```

---

### Task 8: Capability assessment helper

**Files:**
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh` or create `skills/agent-driven-setup/scripts/assess-capabilities.sh`.

**Interfaces:**
- Consumes: list of `required_capabilities` from Setup Contract.
- Produces: `capability_assessment` map.

- [ ] **Step 1: Implement concrete probes**

For each setup-specific capability, determine whether the current Agent/environment can **perform and observe the corresponding verification operation**, independent of whether the target itself passes or fails that operation. Return `available | unavailable | unknown` based on evidence about the environment, not the target state.

```text
Capability assessment: Can this Agent/environment perform and observe the verification operation?
Verification: Did the target pass that operation?
```

- `target_installation`: `available` only if the script can safely attempt a no-op placement check without mutation. Otherwise `unknown`.
- `target_registration`: `available` only if the script can safely read the target registry without writing. Otherwise `unknown`.
- `agent_discovery_probe`: `available` if the discovery path can be read and the mechanism is observable; `unknown` if dynamic or unobservable.
- `representative_activation_probe`: `available` only after the environment proves it can invoke and observe a representative activation operation; otherwise `unknown`.
- `mcp_runtime_probe`: `available` only if the Agent/environment has a safe mechanism to launch, terminate, and observe the declared MCP runtime/transport. Whether that runtime successfully initializes is a verification result, not a capability-assessment result. If a safe probe mechanism is not available, `unknown`.
- `mcp_client_registration`: `available` only if the exact target client config path is known and the Agent/environment can perform the registration operation non-destructively. If the path is unknown or the operation cannot be safely observed, `unknown`.
- `client_reload_new_session`: `available` only if the current Agent/environment can actually control and observe the required client reload or new-session lifecycle. If the operation is known to require an external actor, `unavailable`; if control/observability cannot be established, `unknown`.
- `hook_registration`: `available` only if a safe read-only hook probe is possible; otherwise `unknown`.
- `external_health_check`: `available` if the Agent can issue a read-only request to the declared health endpoint and observe the response. A `500` response from the target does **not** make the capability `unavailable`; it makes the corresponding verification item fail.
- `artifact_secret_lifecycle`: `available` only if safe input, storage, commit prevention, redaction, and cleanup can all be satisfied in this environment. Otherwise `unknown`.


- [ ] **Step 2: Record status, reason, evidence**

Each capability returns `available | unavailable | unknown` with a human-readable reason and optional evidence list.

- [ ] **Step 3: Add tests**

Test that capability status correctly drives verification decisions without conflating capability availability and target failure:
1. `unavailable` capability → dependent verification item is `not_verified` with handoff.
2. `unknown` capability → dependent verification item is `not_verified` with handoff.
3. `available` capability + target operation failure (e.g., MCP initialize error) → capability stays `available`; dependent verification item is `not_verified` with runtime failure reason.

- [ ] **Step 4: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/agent-driven-setup/scripts/verify-setup.sh
git commit -m "feat: add setup-specific capability assessment probes"
```

---

### Task 9: Update `SKILL.md` verification and handoff sections

**Files:**
- Modify: `skills/agent-driven-setup/SKILL.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: SKILL.md sections for verification execution, capability assessment, and handoff reporting.

- [ ] **Step 1: Add capability assessment step**

After audit, add a step that maps Setup Contract `required_capabilities` to `setup-capability-matrix.md` and assesses availability using concrete probes. If a capability is `unavailable` or `unknown`, do not execute the dependent verification speculatively; mark the item `not_verified` and emit the applicable handoff. Only `available` capabilities may proceed to verification execution (subject to `blocked_by` and safety gates).

- [ ] **Step 2: Add verification execution step**

Run target-specific E2E chains. For each phase:
- Skip if `blocked_by` item is not `verified`.
- If the required capability is `unavailable` or `unknown`, mark `not_verified` and emit handoff.
- If the capability is `available` and the operation is safe, execute the representative operation.
- Record evidence. If the target fails the operation (e.g., MCP initialize error, health check 500), the capability remains `available` and the verification item is marked `not_verified` with a runtime failure reason.

- [ ] **Step 3: Add handoff generation step**

For each `not_verified` item with a `handoff_id`, produce a handoff block with actor, action, prerequisites, expected outcome, required evidence. Add it to the verification report, not to the Setup Contract.

- [ ] **Step 4: Add final report section**

Report must include:
- implementation completion status
- verification completion status (per target and item)
- E2E status
- unverified items with handoffs
- dry-run invariant status
- external effects and handoff map

- [ ] **Step 5: Add tests**

Verify new section headers exist.

- [ ] **Step 6: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/agent-driven-setup/SKILL.md
git commit -m "docs: add verification execution, capability assessment, and handoff sections to SKILL.md"
```

---

### Task 10: Final verification and integration readiness

**Files:**
- Read-only verification.
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

- [ ] **Step 1: Run full test suite**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 2: Run skill validation**

```bash
node scripts/validate-skills.js
```

Expected: 0 errors, 0 warnings.

- [ ] **Step 3: Inspect diff**

```bash
git diff --stat
```

Expected: only intended files changed.

- [ ] **Step 4: Commit fixes if any**

```bash
git add ...
git commit -m "fix: address Spec 2 review findings"
```

---

## Self-Review Checklist

- [ ] `setup-capability-matrix.md` does not redefine generic capability availability.
- [ ] Default profiles use `commonly_used`, not `required`/`optional`.
- [ ] `verify-setup.sh --dry-run` only executes read-only or pre-approved ephemeral operations.
- [ ] Unknown commands are `not_executed` during dry-run.
- [ ] Snapshot targets come from concrete mutation surfaces, not whole home directory.
- [ ] Capability assessment returns `available | unavailable | unknown` without deriving from prerequisites.
- [ ] Verification report keeps `e2e_status` as a derived value.
- [ ] Handoff completion and evidence evaluation are separated from verification item status.
- [ ] No P2 eval expansion is included.

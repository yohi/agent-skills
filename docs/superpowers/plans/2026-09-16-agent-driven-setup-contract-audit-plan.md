# Agent-driven Setup — Spec 1: Setup Contract and Cross-layer Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the normative Setup Contract v1, deterministic contract discovery, and read-only cross-layer audit required for complex setup verification.

**Architecture:** `setup-contract-schema.md` is the sole schema authority. `audit-contract.sh` parses only that YAML frontmatter, discovers it with the specified protocol, and emits the fixed Audit Report interface. It never writes to the target repository. Spec 2 consumes its report but does not change audit findings into runtime status.

**Tech Stack:** Bash 4+, Python 3, PyYAML `>=6.0,<7`, Markdown, YAML frontmatter.

## Global Constraints

- P0 and P1 only. Do not modify `evals/evals.json` or eval cases.
- The Setup Contract v1 schema and discovery protocol in the design are normative.
- PyYAML is a runtime dependency; scripts preflight it and never install it.
- `audit-contract.sh` performs no target-repository writes.
- All target paths are repository-relative and may not escape the target root.
- The existing simple-repository path remains unchanged.
- Do not create AI agent configuration files.

---

## File Structure

| File | Responsibility |
|---|---|
| `skills/agent-driven-setup/references/setup-contract-schema.md` | Reproduces the normative v1 key, reference, path, and discovery rules. |
| `skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml` | Valid MCP Contract v1 fixture. |
| `skills/agent-driven-setup/requirements.txt` | Runtime PyYAML range. |
| `skills/agent-driven-setup/scripts/audit-contract.sh` | Deterministic discovery, schema validation, static audit, and fixed report output. |
| `skills/agent-driven-setup/scripts/analyze-repo.sh` | Evidence-only `complexity_triggers` producer. |
| `skills/agent-driven-setup/scripts/test-scripts.sh` | Contract and audit regression suite. |
| `skills/agent-driven-setup/references/*.md`, `SKILL.md` | Enhanced-workflow guidance only. |

---

### Task 1: Publish Setup Contract v1 and parser ownership

**Files:**
- Create: `skills/agent-driven-setup/references/setup-contract-schema.md`
- Create: `skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml`
- Create: `skills/agent-driven-setup/requirements.txt`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** none.

**Consumes:** Design sections “Setup Contract v1 規範 schema”, “Contract discovery protocol”, and “Parser dependency policy”.

**Produces:** Contract v1 reference, valid MCP fixture, and one-line dependency file containing `PyYAML>=6.0,<7`.

**Interfaces:** `setup_contract_schema_version` is integer `1`; target IDs and verification target keys match; layer and mutation-surface discriminators use the exact design vocabulary; PyYAML missing is `dependency_unavailable` / exit 3.

**RED:**
- [ ] Add `check_setup_contract_fixture_rejects_missing_runtime()` with a copied valid fixture whose `setup_target.mcp_main.runtime` is removed.
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh`.
- [ ] Confirm failure from `assert "runtime" in target` while the schema document and fixture do not yet exist.

**GREEN:**
- [ ] Write the schema reference as a field table, including requiredness, null meaning, IDs, path bases, discriminators, reference semantics, and exact discovery marker `<!-- agent-setup-contract: path -->`.
- [ ] Add the complete MCP fixture and `requirements.txt`.
- [ ] Extend the validation helper to load the fixture with `yaml.safe_load` and assert all required v1 fields, including a valid `mcp_request` probe and mutation surface.
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh` and confirm the fixture test passes.

**REFACTOR:**
- [ ] Extract repeated fixture assertions into one local test helper only if two tests require the same assertion sequence; rerun the suite.

**Commit:**
- [ ] Stage only the three created files and `test-scripts.sh`.
- [ ] Commit: `docs: Setup Contract v1スキーマを定義`.

### Task 2: Implement deterministic discovery and referential validation

**Files:**
- Create: `skills/agent-driven-setup/scripts/audit-contract.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Task 1.

**Consumes:** the v1 fixture, PyYAML dependency file, and contract-discovery protocol.

**Produces:** `audit-contract.sh [--contract <repo-relative-path>] [--format json|markdown|both] [--output-dir <target-external-dir>] <repo-path>` with `contract_discovery`, `schema_errors`, and exit codes 0, 2, 3.

**Interfaces:** explicit path has priority; declaration markers are standalone exact lines in root `AGENTS.md` then `README.md`; marker scan considers only `SETUP-CONTRACT.md` and `docs/**/*.md`; report key is always `discrepancies`.

**RED:**
- [ ] Add fixtures for an explicit contract, conflicting `AGENTS.md`/`README.md` markers, two marker-scan candidates, an escaping `../contract.md` path, undefined `handoff_id`, and cyclic `blocked_by`.
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh`.
- [ ] Confirm failures because `audit-contract.sh` does not exist and the expected JSON fields cannot be read.

**GREEN:**
- [ ] Add PyYAML preflight; print an install handoff to stderr and exit 3 without installing.
- [ ] Parse options before the positional repository path; reject invalid grammar and target-internal `--output-dir` with exit 2.
- [ ] Implement the three discovery stages and validate target IDs, layer shapes, phase references, handoff references, item uniqueness, and `blocked_by` acyclicity.
- [ ] Run the suite and confirm `found`, `not_found`, `ambiguous`, and `contract_error` fixtures emit their exact status and `schema_errors` payloads.

**REFACTOR:**
- [ ] Consolidate discovery result serialization if JSON and Markdown paths diverge; rerun the suite.

**Commit:**
- [ ] Stage only `audit-contract.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: Setup Contract監査の発見と参照検証を追加`.

### Task 3: Implement static topology and fixed Audit Report output

**Files:**
- Modify: `skills/agent-driven-setup/scripts/audit-contract.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Task 2.

**Consumes:** validated Contract v1 layer locators and phase operation references.

**Produces:** read-only `observed_topology`, `discrepancies`, and `next_actions`; every discrepancy contains `finding_state` and non-empty `affected_target_ids`.

**Interfaces:** `env`, `cli`, `generated_config`, and `runtime_consumer` use their v1 field layouts; `confirmed`, `candidate`, and `unresolved` are audit-only states; `--format both` writes both report files outside the target and keeps JSON on stdout.

**RED:**
- [ ] Add a fixture with an absent generated-config key, an indirect runtime consumer, and an unrelated valid target.
- [ ] Run the suite and confirm it fails because no `confirmed` discrepancy with `affected_target_ids` is emitted and Markdown artifacts do not exist.

**GREEN:**
- [ ] Scan every declared branch and phase reference using the required locator fields.
- [ ] Emit `confirmed` for missing concrete references, `candidate` for heuristic disconnects, and `unresolved` for dynamic wiring; never mutate the fixture repository.
- [ ] Implement JSON, Markdown, and both-format output with the fixed top-level keys.
- [ ] Run the suite and confirm the fixture reports the expected state, target IDs, and two external report artifacts.

**REFACTOR:**
- [ ] Share report data construction between JSON and Markdown rendering if their finding counts differ; rerun the suite.

**Commit:**
- [ ] Stage only `audit-contract.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: 静的横断監査レポートを追加`.

### Task 4: Add evidence-only complexity triggers

**Files:**
- Modify: `skills/agent-driven-setup/scripts/analyze-repo.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Task 1.

**Consumes:** design complexity trigger vocabulary.

**Produces:** additive `complexity_triggers: [{id, evidence, note}]` in the existing analysis JSON.

**Interfaces:** existing analysis JSON keys and values are unchanged; triggers never select a workflow mechanically.

**RED:**
- [ ] Add a fixture with an MCP config, multiple config writers, and a webhook URL; assert the three exact trigger IDs.
- [ ] Run the suite and confirm failure because `complexity_triggers` is absent.

**GREEN:**
- [ ] Add deterministic read-only heuristics for the declared evidence.
- [ ] Emit an empty array for a simple fixture and the exact ID/evidence/note shape for the complex fixture.
- [ ] Run the suite and confirm both new cases pass and prior analysis assertions remain unchanged.

**REFACTOR:**
- [ ] Extract only duplicated evidence collection; rerun the suite.

**Commit:**
- [ ] Stage only `analyze-repo.sh` and `test-scripts.sh`.
- [ ] Commit: `feat: setup複雑性の根拠を出力`.

### Task 5: Document the additive enhanced workflow

**Files:**
- Modify: `skills/agent-driven-setup/references/setup-approach-decision-guide.md`
- Modify: `skills/agent-driven-setup/references/repository-investigation-checklist.md`
- Modify: `skills/agent-driven-setup/SKILL.md`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Depends on:** Tasks 1 through 4.

**Consumes:** Contract v1, audit grammar, discovery protocol, and trigger output.

**Produces:** documentation-only enhanced workflow that preserves the simple-repository path.

**Interfaces:** no runtime interface changes; complex repositories use Contract extraction then audit; `not_found` returns to extraction and `ambiguous` requires semantic review.

**RED:**
- [ ] Add documentation assertions for the exact Contract marker syntax, `audit-contract.sh` grammar, mutation-surface investigation, and simple-path preservation.
- [ ] Run the suite and confirm the header/content assertions fail before documentation is updated.

**GREEN:**
- [ ] Document trigger evidence, Contract placement, discovery marker, target type, configuration branches, and mutation surfaces.
- [ ] Document the enhanced flow without changing the existing standard flow.
- [ ] Run the suite and confirm all documentation assertions pass.

**REFACTOR:**
- [ ] Remove duplicated prose while preserving the normative schema reference; rerun the suite.

**Commit:**
- [ ] Stage only the three documentation files and `test-scripts.sh`.
- [ ] Commit: `docs: 強化setup監査ワークフローを追加`.

### Task 6: Verify Spec 1 integration readiness

**Files:**
- Create: none
- Modify: none
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`, `scripts/validate-skills.js`

**Depends on:** Tasks 1 through 5.

**Consumes:** all Spec 1 deliverables.

**Produces:** evidence for the integration checkpoint, not new implementation.

**Interfaces:** record the implementation baseline SHA before Task 1; final scope checks compare that SHA to `HEAD`, not only the working tree.

**RED:**
- [ ] Not applicable: this is a read-only verification task.

**GREEN:**
- [ ] Run `bash skills/agent-driven-setup/scripts/test-scripts.sh` and confirm success.
- [ ] Run `node scripts/validate-skills.js` and confirm 0 errors and 0 warnings.
- [ ] Run `git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD` and confirm the intended Spec 1 paths only.

**REFACTOR:**
- [ ] Not applicable.

**Commit:**
- [ ] Do not create an empty commit; commit only required correction files with `fix: Spec 1統合検証の指摘を修正`.

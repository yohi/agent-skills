# Agent-driven Setup — Spec 1: Setup Contract & Cross-layer Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-_SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Setup Contract schema, `audit-contract.sh`, and complexity-based enhanced workflow to `skills/agent-driven-setup/` so complex setups expose expected topology before changes are made.

**Architecture:** A single YAML frontmatter + Markdown Setup Contract becomes the source of truth for expected setup topology. A new `audit-contract.sh` compares the contract against repository evidence and emits observed topology plus `confirmed/candidate/unresolved` discrepancies. SKILL.md gains an optional enhanced workflow for complex repositories while preserving the existing simple-repo path.

**Tech Stack:** Bash (POSIX-compatible where practical, Bash 4+ for associative features), Python 3 with PyYAML (explicitly permitted skill development dependency), Markdown, YAML frontmatter. All scripts must document PyYAML requirement in comments and fail gracefully with a clear error if it is missing.

## Global Constraints

- P0 + P1 only; P2 eval suite expansion is out of scope.
- Generated framework must remain independent of `yohi/agent-skills` after introduction.
- All `audit-contract.sh` operations must be read-only in the target repository.
- Simple repositories without complexity triggers continue using the existing workflow unchanged.
- Setup Contract placement is repository-policy dependent; do not hard-code `.agent-setup/` paths.
- No absolute paths specific to a user or machine may be committed.
- Do not create new AI agent config files (`.opencode/`, `opencode.json(c)`, etc.).

---

## File Structure

| File | Responsibility |
|---|---|
| `skills/agent-driven-setup/references/setup-contract-schema.md` | Defines YAML frontmatter schema, layer vocabulary, and example Setup Contract. |
| `skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml` | Example Setup Contract fixture used by tests and schema documentation. |
| `skills/agent-driven-setup/scripts/audit-contract.sh` | Reads a Setup Contract, verifies referential integrity, scans repository evidence, emits observed topology and discrepancies. |
| `skills/agent-driven-setup/references/setup-approach-decision-guide.md` | Adds complexity trigger guidance and enhanced workflow selection. |
| `skills/agent-driven-setup/references/repository-investigation-checklist.md` | Adds Setup Contract / target type / mutation surface investigation items. |
| `skills/agent-driven-setup/SKILL.md` | Adds optional enhanced workflow (complexity → contract extraction → audit) without breaking simple-repo path. |
| `skills/agent-driven-setup/scripts/test-scripts.sh` | Adds tests for `audit-contract.sh` output shape and referential integrity. |

---

### Task 1: Create `setup-contract-schema.md` reference

**Files:**
- Create: `skills/agent-driven-setup/references/setup-contract-schema.md`
- Create: `skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: Markdown document describing `setup_contract_schema_version: 1`, frontmatter keys, layer vocabulary, handoff contract, and example contract.

- [ ] **Step 1: Write the reference document**

Create `skills/agent-driven-setup/references/setup-contract-schema.md` with:
- Overview of single-artifact contract (YAML frontmatter + Markdown body).
- Required/optional frontmatter fields.
- `configuration_branches` layer mapping using recommended vocabulary.
- `verification` section with stable item IDs, `blocked_by`, `required_for_e2e`, `required_capabilities`, `handoff_id`.
- `handoffs` section with `id`, `actor`, `action`, `prerequisites`, `expected_outcome`, `required_evidence`.
- `external_effects` with optional `mutation_surfaces` for dry-run snapshot scoping.
- Example full contract for an MCP repository.
- Notes on repository-policy-driven placement and discovery.

- [ ] **Step 2: Add a test that validates an example contract fixture**

In `skills/agent-driven-setup/scripts/test-scripts.sh`, add a test step that loads an example Setup Contract fixture (stored under `skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml` or inlined) and asserts `setup_contract_schema_version` is present. Use Python `yaml.safe_load` from PyYAML, which is an explicitly permitted dependency for this skill's scripts. Detect missing PyYAML and print a clear error. Do not treat the schema reference document itself as a Setup Contract.

```bash
python3 - <<'PY'
import sys
from pathlib import Path
try:
    import yaml
except ImportError:
    print("PyYAML is required for Setup Contract parsing; install it for the skill development environment.", file=sys.stderr)
    sys.exit(1)

fixture = Path("skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml")
data = yaml.safe_load(fixture.read_text())
assert data.get("setup_contract_schema_version") == 1, "missing or invalid schema version"
PY
```

- [ ] **Step 3: Run the test to verify it passes**

Run:

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS or at least no failure from the new test.

- [ ] **Step 4: Commit**

```bash
git add \
  skills/agent-driven-setup/references/setup-contract-schema.md \
  skills/agent-driven-setup/references/fixtures/example-setup-contract.yaml \
  skills/agent-driven-setup/scripts/test-scripts.sh
git commit -m "docs: add Setup Contract schema reference"
```

---

### Task 2: Create `audit-contract.sh`

**Files:**
- Create: `skills/agent-driven-setup/scripts/audit-contract.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Consumes: `--contract <path>` or repository-discovered contract file.
- Produces: JSON to stdout with `contract_discovery`, `observed_topology`, `discrepancies`, `schema_errors`, `next_actions`.

- [ ] **Step 1: Write the script skeleton**

Create `skills/agent-driven-setup/scripts/audit-contract.sh` with:
- `set -euo pipefail`
- Argument parsing: `REPO_PATH`, optional `--contract`
- Functions: `fail(msg)` that prints JSON error to stderr and exits 1.

- [ ] **Step 2: Implement Contract discovery**

Implement discovery priority:
1. explicit `--contract` path
2. repository-declared canonical contract path (read from `AGENTS.md` or README section)
3. marker scan for files with `setup_contract_schema_version` in `docs/`, `scripts/`, repo root
4. if not found: emit `contract_discovery.status = not_found` and exit 0 with no findings
5. if multiple ambiguous: `contract_discovery.status = ambiguous`

Output the discovery block as the first field of the JSON report.

- [ ] **Step 3: Parse frontmatter and validate schema**

Use Python to parse YAML frontmatter. Validate that:
- `setup_contract_schema_version` is present
- `verification.targets[*].items[*].id` values are unique across the contract
- `verification.targets[*].items[*].blocked_by` IDs exist
- all `handoff_id` references (from verification, registration, discovery, activation, external_effects) resolve to defined `handoffs`
- `required_capabilities` entries are non-empty strings and are referenced consistently within the contract (do not validate against `setup-capability-matrix.md`; that is Spec 2 responsibility)

Report any issues in `schema_errors`.

- [ ] **Step 4: Build observed topology**

For each `configuration_branches[*].layers` entry:
- `env.key`: search `.env.example`, `.env.sample` for key presence
- `cli.option`: grep for option string in `scripts/`, `README.md`, package scripts
- `generated_config.path` + `key`: check file existence and key reference
- `runtime_consumer.path` + `symbol`: check file existence and symbol reference
- record `found`, `references`, and `note`

Also verify `installation`/`registration`/`discovery`/`activation` reference targets exist.

- [ ] **Step 5: Detect discrepancies**

For each expected layer reference:
- if declared path/key/symbol does not exist → `finding_state: confirmed`
- if heuristic suggests missing wiring (e.g., option present but no env key) → `finding_state: candidate`
- if dynamic/indirect wiring suspected → `finding_state: unresolved`

Add `next_actions` grouping findings by `Agent semantic review`.

- [ ] **Step 6: Add tests for `audit-contract.sh`**

In `test-scripts.sh`, add:
1. A test repo fixture under `/tmp/` containing a valid Setup Contract; run `audit-contract.sh` and assert `contract_discovery.status == found`.
2. A fixture with a missing contract; assert `not_found`.
3. A fixture with a contract referencing a missing generated config key; assert one `confirmed` discrepancy.
4. A fixture with an undefined `handoff_id`; assert one `schema_errors` entry.

- [ ] **Step 7: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: all new tests pass.

- [ ] **Step 8: Commit**

```bash
git add skills/agent-driven-setup/scripts/audit-contract.sh
# stage test-scripts.sh changes if modified
git commit -m "feat: add audit-contract.sh for static cross-layer audit"
```

---

### Task 3: Update `setup-approach-decision-guide.md` with complexity guidance

**Files:**
- Modify: `skills/agent-driven-setup/references/setup-approach-decision-guide.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: updated decision guide that references complexity triggers and enhanced workflow.

- [ ] **Step 1: Add a complexity section**

Insert a new section near the top:
- Definition of complexity triggers.
- Rule: trigger presence does not automatically select enhanced workflow; Agent uses trigger + repository context.
- Reference to `analyze-repo.sh` output format for triggers.
- When enhanced workflow is chosen, reference `setup-contract-schema.md` and `audit-contract.sh`.

- [ ] **Step 2: Add a verification test**

Add a lightweight test that checks the section header exists:

```bash
if grep -q "## Complexity" skills/agent-driven-setup/references/setup-approach-decision-guide.md; then
  echo "complexity section present"
else
  echo "FAIL: missing complexity section" >&2
  exit 1
fi
```

- [ ] **Step 3: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add skills/agent-driven-setup/references/setup-approach-decision-guide.md
git commit -m "docs: add complexity guidance to setup approach decision guide"
```

---

### Task 4: Update `repository-investigation-checklist.md`

**Files:**
- Modify: `skills/agent-driven-setup/references/repository-investigation-checklist.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: updated checklist including Setup Contract, target type, and mutation surface investigation.

- [ ] **Step 1: Add new checklist sections**

Add sections:
- 11. Setup Contract and complexity
  - existing contract files / markers
  - target type hints (MCP, Skill, Plugin, Hook, CLI, Service)
  - configuration branches and known choices
- 12. Mutation surfaces for dry-run
  - `.env*` files
  - Agent config / Skill / Plugin directories
  - external service state references

- [ ] **Step 2: Add verification test**

Add test that new section numbers and headers exist.

- [ ] **Step 3: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add skills/agent-driven-setup/references/repository-investigation-checklist.md
git commit -m "docs: extend investigation checklist for setup contract and mutation surfaces"
```

---

### Task 5: Update `SKILL.md` with enhanced workflow

**Files:**
- Modify: `skills/agent-driven-setup/SKILL.md`
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: SKILL.md with optional enhanced workflow that does not affect simple-repo path.

- [ ] **Step 1: Insert complexity determination step**

After Step 2 (Investigate the repository), add Step 2.5:
- Run `analyze-repo.sh`.
- If `complexity_triggers` empty and one-command install path clear, use standard workflow.
- Otherwise use enhanced workflow.
- Ask user only when ambiguity materially affects scope.

- [ ] **Step 2: Insert Setup Contract extraction step**

Add Step 3 (enhanced) before existing Step 3:
- For complex setups, create/update a Setup Contract using `setup-contract-schema.md`.
- Respect repository documentation policy for placement.
- Define setup intent, targets, branches, writers/consumers, verification items, handoffs.

- [ ] **Step 3: Insert audit step**

Add Step 4 (enhanced):
- Run `audit-contract.sh <repo-path>`.
- Review `confirmed`, `candidate`, `unresolved`.
- Treat `confirmed` as established static discrepancies; determine gap classification from repository context.
- Apply fixes to repository code or contract as appropriate; do not auto-apply.

- [ ] **Step 4: Renumber subsequent steps only if necessary**

Keep existing simple workflow intact; use explicit labels like `(enhanced)` to avoid renumbering confusion.

- [ ] **Step 5: Add test verifying workflow sections exist**

Test for new section headers in SKILL.md.

- [ ] **Step 6: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/agent-driven-setup/SKILL.md
git commit -m "docs: add enhanced workflow for setup contract and audit"
```

---

### Task 6: Update `analyze-repo.sh` to surface complexity triggers

**Files:**
- Modify: `skills/agent-driven-setup/scripts/analyze-repo.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Produces: JSON output with a new `complexity_triggers` array.

- [ ] **Step 1: Detect trigger evidence**

Add detection heuristics:
- Multiple configuration files with overlapping keys (e.g., `.env.example` + multiple config generators).
- Presence of `mcpServers` or `mcp` in known config files.
- Presence of `SKILL.md` in non-meta directories (potential Skill install target).
- Multiple distinct `scripts/` bootstrap/config scripts.
- External service references (urls, gateways, webhooks).
- Secret-bearing env templates with many keys.

Emit as `complexity_triggers` array with `id`, `evidence`, `note`.

- [ ] **Step 2: Keep output backward compatible**

Existing keys remain unchanged; `complexity_triggers` is additive.

- [ ] **Step 3: Add tests**

Create fixture repos and assert expected triggers are detected.

- [ ] **Step 4: Run tests**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/agent-driven-setup/scripts/analyze-repo.sh
git commit -m "feat: surface complexity triggers in analyze-repo.sh"
```

---

### Task 7: Final verification and integration readiness

**Files:**
- Modify: none (read-only verification)
- Test: `skills/agent-driven-setup/scripts/test-scripts.sh`

- [ ] **Step 1: Run full script test suite**

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: all tests pass.

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

- [ ] **Step 4: Commit any final fixes**

If fixes are needed:

```bash
git add ...
git commit -m "fix: address Spec 1 review findings"
```

---

## Self-Review Checklist

- [ ] `setup-contract-schema.md` covers all frontmatter keys from the design doc.
- [ ] `audit-contract.sh` is fully read-only and reports `not_found`/`ambiguous` discovery states.
- [ ] `audit-contract.sh` does not evaluate capability availability (Spec 2 responsibility).
- [ ] `finding_state` definitions match design doc exactly.
- [ ] `SKILL.md` enhanced workflow is additive and simple-repo path unchanged.
- [ ] `analyze-repo.sh` complexity triggers are evidence-only, not a mechanical score.
- [ ] No P2 eval expansion is included.
- [ ] No new AI agent config files are created.

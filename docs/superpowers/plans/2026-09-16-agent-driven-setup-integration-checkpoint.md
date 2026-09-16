# Agent-driven Setup — Integration Checkpoint for Issue #12 P0+P1

**Goal:** Prove that Spec 1 static audit and Spec 2 runtime verification consume the same Setup Contract v1 without expanding into P2.

**When to run:** Record the implementation baseline before the first implementation task, then run this checkpoint after both implementation plans have passed their task-level verification.

## Implementation Baseline and Scope Guard

Before implementing either plan, record the current commit once and preserve it in the execution log:

```bash
IMPLEMENTATION_BASE_SHA="$(git rev-parse HEAD)"
```

Final scope validation must inspect both committed and uncommitted changes. Do not use a bare `git diff` as the implementation scope check.

```bash
git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD
git diff --stat "$IMPLEMENTATION_BASE_SHA"...HEAD
git diff --name-only
git diff --cached --name-only
git ls-files --others --exclude-standard
```

Permitted implementation paths are exactly these prefixes and files:

```text
skills/agent-driven-setup/SKILL.md
skills/agent-driven-setup/requirements.txt
skills/agent-driven-setup/references/
skills/agent-driven-setup/scripts/analyze-repo.sh
skills/agent-driven-setup/scripts/audit-contract.sh
skills/agent-driven-setup/scripts/run-target-probes.sh
skills/agent-driven-setup/scripts/test-scripts.sh
skills/agent-driven-setup/scripts/verify-setup.sh
```

Any other implementation-delta path requires an explicit scope decision before sign-off. The four planning documents on the review branch predate `IMPLEMENTATION_BASE_SHA` and are therefore excluded from this implementation delta.

Apply the following guard to the union of committed, staged, unstaged, and untracked paths. It exits nonzero for every path outside the permitted list, including P2 eval files.

```bash
set -o pipefail
is_allowed_implementation_path() {
  case "$1" in
    skills/agent-driven-setup/SKILL.md|\
    skills/agent-driven-setup/requirements.txt|\
    skills/agent-driven-setup/references/*|\
    skills/agent-driven-setup/scripts/analyze-repo.sh|\
    skills/agent-driven-setup/scripts/audit-contract.sh|\
    skills/agent-driven-setup/scripts/run-target-probes.sh|\
    skills/agent-driven-setup/scripts/test-scripts.sh|\
    skills/agent-driven-setup/scripts/verify-setup.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

{
  git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u | while IFS= read -r path; do
  test -z "$path" && continue
  is_allowed_implementation_path "$path" || {
    printf 'FAIL: out-of-scope path: %s\n' "$path" >&2
    exit 1
  }
done
```

---

## Boundary Contract Verification

| Boundary | Automated evidence | Required result |
|---|---|---|
| Contract schema → audit | `test-scripts.sh`: valid fixture, missing `runtime`, invalid layer shape, undefined reference, cyclic `blocked_by`, invalid `required_capabilities` ID shape/duplicate, invalid command/adapter safety enum, unknown layer kind | Contract consumers apply the v1 closed layer enum and probe safety field shapes; Spec 1 validates capability ID shape and item-local uniqueness without matrix lookup; malformed Contract fails with exit 2. |
| Discovery → audit | explicit path, declared marker, zero/one/multiple marker-scan fixtures | `found`, `not_found`, `ambiguous`, and `contract_error` follow the fixed protocol. |
| Audit → verification | affected confirmed, candidate, unresolved, and unaffected-target fixtures | Audit states remain audit data; confirmed blocks only affected target probes; candidate/unresolved block only affected E2E sign-off pending semantic review. |
| Contract → snapshot | path, glob, external resource, missing-surface, and temporary-fixture cleanup fixtures | Only `snapshot: required` local surfaces are expanded; normal verification may use a Contract-defined external `snapshot: required` temporary surface with cleanup, while dry-run and `snapshot: not_supported` operations are not executed. |
| Capability → item | undefined matrix definition, unavailable, unknown, and available-plus-runtime-failure fixtures | Matrix lookup is Spec 2-owned; undefined definitions are `unknown`, availability is retained independently from target result, and only Contract-defined handoffs appear. |
| Probe → report | MCP with explicit tool/arguments/safety and required temporary-surface reference, Skill with public adapter plus safe/unsafe/unknown adapter fixtures, CLI/Service with read-only/mutating/unknown command fixtures, and Plugin/Hook/custom fixtures | `--item` selects exactly one target-local item; `run-target-probes.sh` emits the fixed JSON shape, applies the effective safety policy immediately before process start, maps adapter outcomes deterministically, and respects P1 support boundaries. |
| Safety declaration → execution | Command/adapter `safety` declarations that agree, disagree, or are `mutating`/`unknown`; MCP representative-call `read_only` and `temporary_fixture`; normal and dry-run invocations | Command/adapter safety is a claim, not authorization; known-mutating, unknown, and mismatched argv are never started; MCP representative-call mode enforces its Contract mutation-surface rules; normal rejection is `not_verified` / `safety_blocked`; dry-run rejection is `not_executed`. |
| Handoff definition → execution record | defined and absent `handoff_id` fixtures | Contract owns definition; report holds execution; undefined handoffs are never invented. |
| CLI/output → consumer | stdout JSON, `--report`, malformed arguments, and target-internal report fixtures | stdout stays backward compatible; Markdown report is external; exits follow the design policy. |

---

## Integration Test Matrix

| Scenario | Preconditions | Automated procedure | Expected result |
|---|---|---|---|
| Simple repository | No trigger and no Contract; PyYAML is unavailable | Run existing `verify-setup.sh <repo>` fixture through the legacy path | Existing JSON keys and behavior are unchanged; no PyYAML handoff, Contract parse, or Contract creation occurs. |
| Contract discovery | Explicit, declared, marker-scan, ambiguous, and malformed fixtures | Run `audit-contract.sh` per fixture | Exact discovery status and source; no prose inference. |
| Static disconnect | Contract has missing generated-config key for target A | Run audit then verification | Audit emits target-A `confirmed`; target A is `audit_blocked`; target B can proceed. |
| Unresolved static wiring | Dynamic consumer fixture for target A | Run audit then verification | `unresolved` remains audit data; target A E2E is `not_verified` until semantic review. |
| Capability unavailable | Valid MCP contract but no safe runtime mechanism | Run verification fixture | Capability is `unavailable`; item is `not_verified`; applicable Contract handoff is recorded. |
| Runtime failure | Safe MCP probe mechanism, initialize returns error | Run verification fixture | Capability remains `available`; item is `not_verified` with `runtime_failure`; exit 4. |
| MCP P1 chain | Stdio fixture supports initialize, tools/list, and a safe tool call; the representative item declares `tool`, `arguments`, `safety`, and a required external `snapshot: required` / `cleanup_required: true` `mutation_surface_id` when temporary data is used | Run target probe once per verification item ID in normal mode, then run dry-run admission | Each item yields evidence in normal mode; declared `temporary_fixture` is allowed only in normal mode with cleanup; dry-run marks it `not_executed`; target E2E is derived from items and no phase-only selection occurs. |
| Normal temporary fixture | MCP representative call uses an external `temporary_fixture` surface with `snapshot: required`, `cleanup_required: true`, and an applicable predefined cleanup path, then uses a fixture that fails cleanup | Run normal target probe and inspect the fixed JSON result | The declared temporary mutation executes and is cleaned; unsupported cleanup is blocked before operation start; cleanup failure is `not_verified` / `safety_blocked`; no persistent external mutation remains. |
| Skill P1 chain | Observable agent discovery/activation fixture with Contract-provided public adapter `argv`, plus safe, unsafe, and unknown-safety adapters | Run discovery and activation probes by item ID | Only the safe adapter is started; unsafe/unknown/mismatched adapters are not started and return `not_verified` / `safety_blocked`; the adapter is invoked without a shell; statuses remain separate. |
| Generic P1 boundary | CLI/Service fixtures for known read-only, known-mutating, and unknown command signatures, plus Plugin/Hook/custom fixture | Run probes in normal mode and safety admission in dry-run | Only known read-only commands run; known-mutating/unknown commands are `not_verified` / `safety_blocked` in normal mode and `not_executed` in dry-run; unsupported types return only defined handoff. |
| Pristine dry-run | Git fixture without `.agent-setup` | Run `verify-setup.sh --dry-run`; inspect existence and Git status | No cache or tracked/untracked mutation; only effective `read_only` probes execute. |
| Dry-run violation | Known-read-only fixture unexpectedly writes a tracked file | Run dry-run verification | `dry_run_invariant_violation`, cleanup, and exit 1; intentionally temporary, mutating, and unknown operations are suppressed before process start. |
| Report destination | Valid target with external and internal report paths | Run with each `--report` path | External report works while stdout remains JSON; internal path is exit 2 in dry-run. |
| Dependency unavailable | PATH fixture without importable PyYAML, with both an enhanced Contract fixture and a no-trigger/no-Contract simple fixture | Run audit and enhanced verification, then the legacy simple verification | Audit and enhanced verification make no install attempt and return exit 3 with provisioning handoff; simple verification preserves the legacy path without PyYAML. |

---

## Acceptance Criteria Mapping

| # | Criterion | Concrete verification |
|---|---|---|
| 1 | Complex setup exposes a Setup Contract | Valid complex fixture parsed by `audit-contract.sh`. |
| 2 | Triggers include representative and unknown-equivalent cases | `analyze-repo.sh` fixture asserts evidence-only trigger shape; `SKILL.md` procedure documents Agent override. |
| 3 | Chosen configuration reaches consumer/activation | Branch-layer fixture verifies `env`, `cli`, generated config, and runtime consumer locators. |
| 4 | Unchosen public branches are audited | Multi-branch fixture asserts every declared branch is scanned. |
| 5 | Artifact placement alone is not E2E success | Report fixture requires a verified representative-operation item. |
| 6 | Target-specific representative operation is in Contract | Schema fixture rejects required item without a `probe`. |
| 7 | Skill install, discovery, activation are separate | Skill fixture asserts three independent item statuses. |
| 8 | Observable Skill activation is verified | Contract-defined public adapter for `agent_action: activation` returns observable evidence. |
| 9 | Unobservable Skill activation is not verified | Capability-unknown fixture keeps discovery and activation separate. |
| 10 | MCP includes initialize, discovery, and possible tool call | Stdio MCP fixture exercises the three P1 items; representative call uses Contract-defined `tool`, `arguments`, and `safety`. |
| 11 | Generic targets reach their supported boundary | CLI/Service read-only/mutating/unknown safety fixtures and unsupported-type handoff fixture. |
| 12 | Unsafe E2E is not success | unavailable/unknown capability and safety-blocked probe fixtures produce `not_verified`; no unsafe process starts. |
| 13 | Implementation and verification completion are distinct | Markdown report fixture asserts distinct sections. |
| 14 | Major verification statuses are retained | Multi-item report fixture asserts every item `status`. |
| 15 | Unverified items carry actionable evidence | Defined-handoff fixture asserts reason, next step, required evidence, and applicable handoff only. |
| 16 | Dry-run makes no persistent mutation | Pristine dry-run fixture checks `.agent-setup` absence and Git status. |
| 17 | Dry-run skips installation/registration and mutation | `npm install`, registration, temporary-fixture, mutating, and unknown command/adapter fixtures are `not_executed`; only known read-only probes execute. |
| 18 | Canonical source supports mutable/immutable references | Schema fixtures validate `canonical_source.ref_mode` and `ref` rules. |
| 19 | Matrix separates install/discovery/activation | Matrix reference assertions cover the three capability names and an undefined matrix ID becomes `unknown`. |
| 20 | Repository gaps can be classified | Audit fixture asserts bootstrap/configuration/runtime classifications in `next_actions`. |
| 21 | Behavior changes have fail-first evidence | Each behavior task records RED command/failure and GREEN command/success in both plans; implementation log attaches outputs. |
| 22 | Unautomatable exceptions are explicit | Unsupported target fixture records not-verified status and Contract-defined handoff. |
| 23 | Repository policy overrides generic defaults | Explicit and declared discovery fixtures beat marker scanning. |
| 24 | Existing setup remains intact | Simple-repository regression fixture and audit read-only assertion. |
| 25 | Semantic backward compatibility remains | Default stdout JSON regression fixture retains existing keys. |
| 26 | Simple repositories avoid heavyweight verification | Empty-trigger fixture follows the unchanged standard workflow without a PyYAML preflight. |
| 27 | P2 does not expand | Baseline-delta eval scope guard succeeds. |

---

## Final Commands

Run from repository root after both plans complete:

```bash
node scripts/validate-skills.js
python3 -m pip install -r skills/agent-driven-setup/requirements.txt
bash skills/agent-driven-setup/scripts/test-scripts.sh
git diff --name-only "$IMPLEMENTATION_BASE_SHA"...HEAD
git diff --stat "$IMPLEMENTATION_BASE_SHA"...HEAD
git status --short
git diff --name-only
git diff --cached --name-only
git ls-files --others --exclude-standard
```

The dependency-install command provisions the CI or caller environment only. It must not run inside, or install into, a target repository under test.

## Sign-Off Definition

Integration passes only when all conditions are met:

1. `node scripts/validate-skills.js` returns 0 errors and 0 warnings.
2. PyYAML `>=6.0,<7` is available in the caller or ephemeral CI environment; neither script installed it.
3. `bash skills/agent-driven-setup/scripts/test-scripts.sh` passes every matrix scenario.
4. Every acceptance criterion has the mapped automated fixture or the mapped documented procedure and retained execution evidence.
5. The baseline-to-HEAD, staged, unstaged, and untracked paths all pass `is_allowed_implementation_path`; no P2 eval path exists.
6. `git status --short` is empty, apart from explicitly documented final evidence artifacts outside the repository.
7. No new AI agent config file is created.

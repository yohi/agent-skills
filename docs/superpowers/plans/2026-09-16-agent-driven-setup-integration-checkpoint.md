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
| Contract schema → audit | `test-scripts.sh`: valid fixture, missing `runtime`, invalid layer shape, undefined reference, cyclic `blocked_by` | Both scripts parse Contract v1 or fail with exit 2; all IDs and references resolve. |
| Discovery → audit | explicit path, declared marker, zero/one/multiple marker-scan fixtures | `found`, `not_found`, `ambiguous`, and `contract_error` follow the fixed protocol. |
| Audit → verification | affected confirmed, candidate, unresolved, and unaffected-target fixtures | Audit states remain audit data; confirmed blocks only affected target probes; candidate/unresolved block only affected E2E sign-off pending semantic review. |
| Contract → snapshot | path, glob, external resource, and missing-surface fixtures | Only `snapshot: required` local surfaces are expanded; external/not-supported operations are not executed. |
| Capability → item | unavailable, unknown, and available-plus-runtime-failure fixtures | Availability is retained independently from target result; only Contract-defined handoffs appear. |
| Probe → report | MCP, Skill, CLI/Service, and Plugin/Hook/custom fixtures | `run-target-probes.sh` emits the fixed JSON shape; P1 support boundaries are respected. |
| Handoff definition → execution record | defined and absent `handoff_id` fixtures | Contract owns definition; report holds execution; undefined handoffs are never invented. |
| CLI/output → consumer | stdout JSON, `--report`, malformed arguments, and target-internal report fixtures | stdout stays backward compatible; Markdown report is external; exits follow the design policy. |

---

## Integration Test Matrix

| Scenario | Preconditions | Automated procedure | Expected result |
|---|---|---|---|
| Simple repository | No trigger and no Contract | Run existing `verify-setup.sh <repo>` fixture | Existing JSON keys and behavior are unchanged; no Contract is created. |
| Contract discovery | Explicit, declared, marker-scan, ambiguous, and malformed fixtures | Run `audit-contract.sh` per fixture | Exact discovery status and source; no prose inference. |
| Static disconnect | Contract has missing generated-config key for target A | Run audit then verification | Audit emits target-A `confirmed`; target A is `audit_blocked`; target B can proceed. |
| Unresolved static wiring | Dynamic consumer fixture for target A | Run audit then verification | `unresolved` remains audit data; target A E2E is `not_verified` until semantic review. |
| Capability unavailable | Valid MCP contract but no safe runtime mechanism | Run verification fixture | Capability is `unavailable`; item is `not_verified`; applicable Contract handoff is recorded. |
| Runtime failure | Safe MCP probe mechanism, initialize returns error | Run verification fixture | Capability remains `available`; item is `not_verified` with `runtime_failure`; exit 4. |
| MCP P1 chain | Stdio fixture supports initialize, tools/list, safe tool call | Run target probe for all three phases | Each phase yields evidence; target E2E is derived from items. |
| Skill P1 chain | Observable agent discovery/activation fixture | Run discovery and activation probes | Statuses remain separate; unavailable activation is not success. |
| Generic P1 boundary | CLI/Service read-only fixture and Plugin/Hook/custom fixture | Run probes | CLI/Service command probe runs read-only; unsupported types return only defined handoff. |
| Pristine dry-run | Git fixture without `.agent-setup` | Run `verify-setup.sh --dry-run`; inspect existence and Git status | No cache or tracked/untracked mutation; only known read-only commands execute. |
| Dry-run violation | Approved ephemeral fixture writes a tracked file | Run dry-run verification | `dry_run_invariant_violation`, cleanup, and exit 1. |
| Report destination | Valid target with external and internal report paths | Run with each `--report` path | External report works while stdout remains JSON; internal path is exit 2 in dry-run. |
| Dependency unavailable | PATH fixture without importable PyYAML | Run audit and verification | No install attempt; exit 3 and provisioning handoff. |

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
| 8 | Observable Skill activation is verified | Observable `agent_action: activation` fixture returns evidence. |
| 9 | Unobservable Skill activation is not verified | Capability-unknown fixture keeps discovery and activation separate. |
| 10 | MCP includes initialize, discovery, and possible tool call | Stdio MCP fixture exercises the three P1 phases. |
| 11 | Generic targets reach their supported boundary | CLI/Service read-only fixture and unsupported-type handoff fixture. |
| 12 | Unsafe E2E is not success | unavailable/unknown capability fixtures produce `not_verified`. |
| 13 | Implementation and verification completion are distinct | Markdown report fixture asserts distinct sections. |
| 14 | Major verification statuses are retained | Multi-item report fixture asserts every item `status`. |
| 15 | Unverified items carry actionable evidence | Defined-handoff fixture asserts reason, next step, required evidence, and applicable handoff only. |
| 16 | Dry-run makes no persistent mutation | Pristine dry-run fixture checks `.agent-setup` absence and Git status. |
| 17 | Dry-run skips installation/registration | `npm install` and registration command fixtures are `not_executed`. |
| 18 | Canonical source supports mutable/immutable references | Schema fixtures validate `canonical_source.ref_mode` and `ref` rules. |
| 19 | Matrix separates install/discovery/activation | Matrix reference assertions cover the three capability names. |
| 20 | Repository gaps can be classified | Audit fixture asserts bootstrap/configuration/runtime classifications in `next_actions`. |
| 21 | Behavior changes have fail-first evidence | Each behavior task records RED command/failure and GREEN command/success in both plans; implementation log attaches outputs. |
| 22 | Unautomatable exceptions are explicit | Unsupported target fixture records not-verified status and Contract-defined handoff. |
| 23 | Repository policy overrides generic defaults | Explicit and declared discovery fixtures beat marker scanning. |
| 24 | Existing setup remains intact | Simple-repository regression fixture and audit read-only assertion. |
| 25 | Semantic backward compatibility remains | Default stdout JSON regression fixture retains existing keys. |
| 26 | Simple repositories avoid heavyweight verification | Empty-trigger fixture follows the unchanged standard workflow. |
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

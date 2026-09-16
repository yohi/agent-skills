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
set -e
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
| Contract schema → audit | `test-scripts.sh`: valid fixture, missing `runtime`, missing process `runtime.command` / `runtime.safety`, invalid layer shape, undefined reference, cyclic `blocked_by`, invalid `required_capabilities` ID shape/duplicate, invalid command/adapter/runtime safety enum, unknown layer kind | Contract consumers apply the v1 closed layer enum and probe safety field shapes; Spec 1 validates process-only runtime safety requiredness plus capability ID shape and item-local uniqueness without matrix lookup; malformed Contract fails with exit 2. |
| Discovery → audit | explicit path, declared marker, zero/one/multiple marker-scan fixtures | `found`, `not_found`, `ambiguous`, and `contract_error` follow the fixed protocol. |
| Audit → verification | affected confirmed, candidate, unresolved, and unaffected-target fixtures | Audit states remain audit data; confirmed blocks only affected target probes; candidate/unresolved block only affected E2E sign-off pending semantic review. |
| Contract → snapshot | path, glob, external resource, missing-surface, and unsupported temporary-fixture fixtures | Only `snapshot: required` local surfaces are expanded; external resources and Contract-defined `temporary_fixture` remain visible in the Contract but are not automatically operated or cleaned up in P1; dry-run and `snapshot: not_supported` operations are not executed. |
| Capability → item | undefined matrix definition, unavailable, unknown, and available-plus-runtime-failure fixtures | Matrix lookup is Spec 2-owned; undefined definitions are `unknown`, availability is retained independently from target result, and only Contract-defined handoffs appear. |
| Probe → report | MCP with explicit tool/arguments/`read_only` safety and the exact safe runtime fixture, an unsupported `temporary_fixture`, Skill with a Contract-defined handoff fixture, CLI/Service with the named Policy v1 command fixtures, and Plugin/Hook/custom fixtures | `--item` selects exactly one target-local item; `run-target-probes.sh` emits the fixed JSON shape, applies the effective safety policy immediately before supported process start, maps runtime outcomes deterministically, emits no Skill adapter process, and respects P1 support boundaries. |
| Safety declaration → execution | Command/adapter/runtime `safety` declarations that agree, disagree, or are `mutating`/`unknown`; a declared-safe Skill adapter; MCP representative-call `read_only` and unsupported `temporary_fixture`; normal and dry-run invocations | Safety is a claim, not authorization; the Policy v1 classifier marks exact known-mutating, unknown, and mismatched argv as non-executable; P1 Skill support boundary is applied before adapter execution admission, so a Skill adapter is handed off without adapter start even when classified `read_only`; MCP runtime start is admitted only for matching effective `read_only`; MCP `temporary_fixture` is blocked before runtime, operation, and cleanup; normal rejection is `not_verified` / `safety_blocked`; dry-run Skill adapter rejection is `not_executed`. |
| Probe Safety Policy v1 → classifier → admission | `node --version`, `git status --porcelain`, exact MCP runtime `agent-setup-mcp-stdio-readonly`, a declared-safe Skill adapter, `npm install`, `unknown-command --check`, absolute-path and wrapper variants, each paired with normal and dry-run invocation | `run-target-probes.sh` is the sole classifier owner; normal final-gate and dry-run `--classify-only` return identical `effective_safety` and `declaration_matches` for identical argv, with only execution policy differing; P1 Skill adapters may be classified in dry-run but the support boundary maps them to `not_executed` and never starts an adapter process; MCP runtime is classified in dry-run but never started there. |
| Runtime contract → MCP process-start admission | `runtime.mode: process`, exact safe runtime fixture with its stdin/stdout JSON-RPC contract, mutating/unknown/mismatched runtime variants, and a process-start marker outside the target repository | The same classifier receives `runtime.command` and `runtime.safety`; normal verification starts only the exact matching `read_only` fixture, sends `initialize`, `tools/list`, and the Contract-selected read-only call, and observes each response; every other runtime is rejected before process start with `not_verified` / `safety_blocked`; dry-run performs classification-only and records `not_executed` without starting a runtime. |
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
| Runtime failure | Exact safe MCP runtime fixture passes startup admission, initialize returns error | Run verification fixture | Capability remains `available`; item is `not_verified` with `runtime_failure`; exit 4. |
| MCP P1 chain | Stdio fixture supports initialize, tools/list, and a safe `read_only` tool call; `runtime.command` is exactly `agent-setup-mcp-stdio-readonly` with `runtime.safety: read_only`; the representative item declares `tool`, `arguments`, and `safety: read_only` | Run target probe once per verification item ID in normal mode, then run dry-run admission | Normal verification classifies and admits the exact runtime before starting it, then yields evidence for each supported item; `temporary_fixture` is not a P1 operation; dry-run classifies the runtime but marks the entire MCP chain `not_executed` without starting a process; target E2E is derived from items and no phase-only selection occurs. |
| Unsupported temporary fixture | MCP representative call declares an external `temporary_fixture` surface with `snapshot: required` and `cleanup_required: true`, with and without a Contract-defined handoff | Run normal target probe and dry-run admission | Normal verification starts neither the runtime process, representative operation, nor cleanup and returns `not_verified` / `safety_blocked`, emitting only the defined handoff; dry-run returns `not_executed`; no external mutation occurs. |
| Skill P1 chain | Skill discovery/activation item has Contract-defined handoff and Contract adapter data, but no selected concrete public Agent seam | Run discovery and activation probes by item ID in normal mode and dry-run | Neither discovery nor activation adapter starts in P1; normal mode returns `not_verified` / `safety_blocked` and emits only its defined handoff, while dry-run returns `dry_run.decision: not_executed` without an adapter process; when a handoff is defined, dry-run includes only its definition as reference and does not create an execution record. |
| Generic P1 boundary | Policy v1 exact fixtures `node --version`, `git status --porcelain`, exact MCP runtime `agent-setup-mcp-stdio-readonly`, `npm install`, `unknown-command --check`, absolute-path/wrapper variants, plus Plugin/Hook/custom fixture | Run probes in normal mode and safety admission in dry-run | Only the named read-only command probes run in normal mode; the exact MCP runtime may start only in normal mode after its gate; `npm install`, unknown variants, mismatches, and unsupported runtime modes are `not_verified` / `safety_blocked` in normal mode and `not_executed` in dry-run; Skill and unsupported types return only defined handoff. |
| Pristine dry-run | Git fixture without `.agent-setup`, including an MCP contract with the exact safe runtime fixture and a declared-safe Skill adapter | Run `verify-setup.sh --dry-run`; inspect existence and Git status | No cache or tracked/untracked mutation; read-only command probes may execute, while Skill adapter classification produces `not_executed` without starting an adapter process, MCP runtime classification occurs without starting a process, and the MCP chain is `not_executed`. |
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
| 7 | Skill install, discovery, activation are separate | Skill fixture asserts independent install, discovery, and activation item statuses; discovery/activation are P1 handoff boundaries. |
| 8 | Skill discovery/activation handoff is explicit when no concrete safe seam is selected | Contract-defined `agent_action` handoffs are emitted as pending/needs_review; no adapter process starts and no activation is reported `verified` in P1. |
| 9 | Unobservable or unsupported Skill activation is not verified | Skill fixture keeps discovery and activation separate and returns `not_verified` / `safety_blocked` with only defined handoffs. |
| 10 | MCP runtime start, initialize, discovery, and possible tool call have separate safety boundaries | Stdio MCP fixture uses exact `runtime.command: ["agent-setup-mcp-stdio-readonly"]` with `runtime.safety: read_only`; normal mode gates runtime before the three protocol items, while dry-run classifies but does not start the runtime; `temporary_fixture` is explicitly unsupported in P1. |
| 11 | Generic targets reach their supported boundary | CLI/Service read-only/mutating/unknown safety fixtures and unsupported-type handoff fixture. |
| 12 | Unsafe E2E is not success | unavailable/unknown capability, unsafe/unknown/mismatched command or runtime, and Skill handoff fixtures produce `not_verified`; no unsafe runtime or adapter process starts. |
| 13 | Implementation and verification completion are distinct | Markdown report fixture asserts distinct sections. |
| 14 | Major verification statuses are retained | Multi-item report fixture asserts every item `status`. |
| 15 | Unverified items carry actionable evidence | Defined-handoff fixture asserts reason, next step, required evidence, and applicable handoff only. |
| 16 | Dry-run makes no persistent mutation | Pristine dry-run fixture checks `.agent-setup` absence and Git status. |
| 17 | Dry-run skips installation/registration, runtime startup, and mutation | `npm install`, registration, MCP runtime startup, temporary-fixture, mutating, and unknown command/adapter/runtime fixtures are `not_executed`; only supported read-only command probes execute, while P1 Skill adapters are classification-only and never start a process. |
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

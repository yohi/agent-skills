# Agent-driven Setup — Integration Checkpoint for Issue #12 P0+P1

**Goal:** Ensure Spec 1 (Setup Contract & Cross-layer Audit) and Spec 2 (Capability & Verification Execution) work together correctly and satisfy the acceptance criteria of Issue #12 P0+P1, without expanding scope into P2.

**When to run:** After Implementation Plan 1 and Implementation Plan 2 are both complete and each has passed its own verification.

---

## Integration Test Matrix

| Scenario | Spec 1 output | Spec 2 input | Expected result |
|---|---|---|---|
| Simple repo with no triggers | `complexity_triggers` empty, standard workflow recommended | standard `verify-setup.sh` path | no Setup Contract created, existing behavior unchanged |
| Complex MCP repo with valid contract | `contract_discovery: found`, audit `confirmed: 0` | capability assessment, verification report | `e2e_status` follows runtime evidence; unverified items produce handoffs |
| Complex repo with static disconnect | audit emits `confirmed` or `candidate` discrepancy | verification does not claim E2E verified until disconnect resolved | report shows gap classification and required fix |
| Complex repo with unavailable capability | audit passes schema, no static disconnect | capability assessment marks `mcp_runtime_probe: unavailable` | corresponding verification item `not_verified` + handoff |
| Capability available but target operation fails | audit passes schema | `mcp_runtime_probe: available`, MCP initialize executed, server returns error | capability stays `available`; verification item `not_verified` with runtime failure reason |
| Dry-run on mutating setup | `audit-contract.sh` read-only, no runtime execution | `verify-setup.sh --dry-run` classifies install/registration as `not_executed`, snapshot clean | no persistent state changes |
| Dry-run invariant violation | — | `verify-setup.sh --dry-run` detects unexpected mutation | `dry_run_invariant_violation` reported and dry-run fails |
| Handoff lifecycle | Contract defines handoff | Report records handoff completed, evidence acquired, evaluation_result `needs_review` | verification item remains `not_verified` until evaluation passes |

---

## Boundary Contract Verification

Verify that the files produced by Spec 1 are correctly consumed by Spec 2:

1. **Setup Contract schema**
   - `audit-contract.sh` and `verify-setup.sh` parse the same YAML frontmatter keys.
   - `setup_contract_schema_version: 1` is the stable identifier.

2. **Verification item ID stability**
   - IDs generated in Spec 1 are referenced by `blocked_by` and handoffs without change in Spec 2.

3. **Capability requirement flow**
   - Contract declares `required_capabilities`.
   - Spec 2 `capability_assessment` maps each to `available | unavailable | unknown`.
   - `unavailable` or `unknown` capabilities mark the dependent verification item `not_verified` and use the Contract-defined handoff when one is defined/applicable. They never route to false success, and they never invent a handoff that is not defined in the Contract.

4. **Handoff definition vs execution record**
   - Contract contains handoff definitions.
   - Verification report contains handoff execution records with `evaluation_result`.

5. **Mutation surface continuity**
   - Contract `external_effects.mutation_surfaces` matches `verify-setup.sh --dry-run` snapshot targets.

6. **Audit finding state semantics**
   - `confirmed`, `candidate`, `unresolved` from Spec 1 do not directly set Spec 2 verification status; they inform Agent review.

---

## Acceptance Criteria Mapping (Issue #12)

| # | Criterion | Verification method |
|---|---|---|
| 1 | 複雑な setup では Setup Contract が把握される | Complex repo integration test creates/reads contract |
| 2 | complexity trigger が代表例として定義され未知の同等ケースも扱える | `analyze-repo.sh` emits triggers; Agent can override |
| 3 | 選択された設定が user input から actual consumer / activation まで追跡される | Contract branch layer mapping + audit observed topology |
| 4 | 非選択の公開 branch も明白な disconnect が監査される | `audit-contract.sh` checks all declared branches |
| 5 | setup artifact の生成・配置だけを E2E success としない | `verify-setup.sh` requires representative operation evidence |
| 6 | setup target に応じた representative operation が verification contract に含まれる | Contract defines activation/representative_operation |
| 7 | Skill では install、Agent discovery、representative activation を別々に検証可能 | Verification report has separate items |
| 8 | Skill activation を観測可能なら代表 prompt 等による activation verification を行う | `representative_activation_probe` used when available |
| 9 | Skill activation を観測不能なら discovery と activation の status を分離する | `discovery: verified`, `activation: not_verified` in report |
| 10 | MCP では initialize、tool discovery、可能なら representative tool call を含む | MCP verification items cover all four phases |
| 11 | Plugin / Hook / CLI / Service 等も target 固有の利用可能性まで検証可能である | Generic E2E chain applies to `other/custom` target |
| 12 | 安全に実行できない E2E operation を成功扱いしない | Capability `unavailable` or `unknown` → item `not_verified`; Contract-defined handoff if applicable, never false success |
| 13 | implementation completion と verification completion が分離される | Report has separate sections |
| 14 | verification status が主要項目ごとに保持される | `verification.targets[*].items[*].status` |
| 15 | 未検証項目に理由、handoff、次操作、完了証跡が存在する | Every `not_verified` item has `reason`, `next_step`, `required_evidence`, and `handoff_id` when a Contract-defined handoff is applicable |
| 16 | dry-run では永続状態を変更しない | Snapshot + classifier tests |
| 17 | dry-run では Skill install / Plugin registration 等も実行しない | Dry-run classifier test |
| 18 | canonical source が用途に応じて mutable / immutable に使い分けられる | Contract `canonical_source.ref` supports both with note |
| 19 | Capability Matrix が install capability と discovery/activation capability を区別できる | `setup-capability-matrix.md` definitions |
| 20 | Setup Contract 成立に必要な gap は repository 本体も修正対象にできる | Gap classification allows bootstrap/configuration/runtime fixes |
| 21 | 挙動変更には原則 fail-first の回帰証拠が存在する | TDD guidance in `verification-patterns.md` / SKILL.md |
| 22 | 自動化不能な例外は明示され、完全 Verified 扱いにならない | Exception records in verification report |
| 23 | repository 固有 policy が generic default より優先される | Contract placement and target type detection priorities |
| 24 | existing manual setup、CI、Agent setup を破壊しない | Simple repo path unchanged; audit is read-only |
| 25 | 既存利用者との意味的後方互換性を維持する | No forced migration; enhanced workflow is additive |
| 26 | 単純な repository に不要な heavyweight verification を要求しない | Trigger-based gating |
| 27 | Issue #12 P2 へスコープ拡大しない | No `evals.json` expansion in changes |

---

## Integration Test Commands

Run from repository root:

```bash
# 1. Validate all skill metadata
node scripts/validate-skills.js

# 2. Run all agent-driven-setup script tests
bash skills/agent-driven-setup/scripts/test-scripts.sh

# 3. Verify no unintended files changed
git status --short

# 4. Check for P2 scope creep
git diff --name-only | grep -E 'evals/evals\.json|eval.*\.json' && echo "FAIL: P2 scope detected" || echo "OK: no eval expansion"
```

---

## Sign-Off Definition

Integration checkpoint passes when:

1. `node scripts/validate-skills.js` returns 0 errors, 0 warnings.
2. `bash skills/agent-driven-setup/scripts/test-scripts.sh` passes.
3. YAML parser dependency (PyYAML) is documented and available in the test/execution environment used by the integration tests.
4. At least one non-MCP target scenario (Skill is recommended) demonstrates separated statuses: `install: verified`, `discovery: verified`, `activation: not_verified`, with a corresponding handoff.
5. All acceptance criteria in the mapping above have at least one corresponding test or documented procedure.
6. No `evals.json` or eval-case files are modified.
7. No new AI agent config files (`.opencode/`, `opencode.json(c)`, etc.) are created.
8. `git diff --stat` shows only intended files in `skills/agent-driven-setup/`.

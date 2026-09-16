# Agent-driven Setup — 複雑な setup / Setup Target E2E 検証強化

## 概要

この設計は `yohi/agent-skills` リポジトリ内の `skills/agent-driven-setup/` skill を拡張し、Agent 向け README / Protocol や setup artifact の生成・配置に留まらず、**ユーザーが選択した設定が CLI・環境設定・生成設定・runtime まで一貫して接続され、可能な範囲で対象機能が実際に利用可能になったこと**まで検証する仕組みを導入する。

対象は Issue #12 の P0 + P1。P2 の eval ケース拡張は対象外。

---

## 分解構造

本設計は以下に分解する。

| 文書 | 内容 |
|---|---|
| この上位設計 | 2 つの詳細 spec の境界 contract、全体的なアーキテクチャ |
| Spec 1 — Setup Contract & Cross-layer Audit | Setup Contract schema、complexity 判定、target type 識別、`audit-contract.sh`、静的横断監査 |
| Spec 2 — Capability & Verification Execution | `setup-capability-matrix.md`、capability assessment、target-specific E2E、`verify-setup.sh` dry-run 強化、handoff/evidence lifecycle |
| Implementation Plan 1 | Spec 1 の実装計画 |
| Implementation Plan 2 | Spec 2 の実装計画 |
| Integration checkpoint | 同一 Issue #12 / P0+P1 完了条件での統合検証 |

依存方向は **Spec 1 → Spec 2** とする。Spec 2 は Setup Contract schema と audit report を利用するが、Spec 1 は Spec 2 の実行機構に依存しない。

---

## 背景と問題

Issue #12 では、`agent-driven-setup` で ChronosGraph の setup framework を生成した後も、bootstrap、CLI/env、config generator、runtime 間の断線を後から修正する必要があった。

根本的な原因は、**「Protocol に選択肢がある」「setup artifact が生成された」「設定を書いた」「プロセスが起動した」が setup 成功と同一視されていた**こと。

この問題は MCP に限らない。Skill / Plugin / Hook / CLI / Service の setup でも発生し得る。

---

## ユーザー価値

- setup framework 導入後に人間が追加で断線を発見・修正する必要を減らす。
- false-positive な setup completion を減らす。
- Agent 単独では完了できない操作について、未検証部分と次に必要な作業を明確に handoff する。

---

## 3層分離

本設計の中核は次の分離。

| レイヤー | 内容 | 担当 |
|---|---|---|
| **Setup Contract** | 期待される setup topology、required capabilities、handoff 定義 | Agent + `setup-contract-schema.md` |
| **Audit Report** | observed static topology、discrepancy candidate | `audit-contract.sh` + Agent semantic review |
| **Verification Report** | observed runtime result、capability availability、handoff 実行記録 | `verify-setup.sh` + target-specific probes |

Setup Contract に runtime status は置かない。Verification definition は Contract に、status は Verification Report に置く。

---

## Setup Contract

### 単一 source of truth

- YAML frontmatter + Markdown 本文の 1 ファイル。
- 配置場所は repository policy に委ねる。`.agent-setup/...` への固定配置は要求しない。
- YAML frontmatter は機械処理用。Markdown 本文は人間・Agent 向け説明。

### frontmatter marker

```yaml
---
setup_contract_schema_version: 1
...
```

### frontmatter 主要フィールド

- `setup_intent`
- `setup_target`: canonical source、runtime mode
- `complexity_triggers`: 自動検出された trigger の evidence
- `configuration_branches`: branch ごとの layer mapping
- `installation` / `registration` / `discovery` / `activation`
- `verification`: verification item 定義
- `handoffs`: handoff 定義
- `external_effects`: 外部副作用 scope + mutation surfaces

### verification item 定義

```yaml
verification:
  targets:
    mcp_main:
      items:
        - id: mcp.initialize
          phase: initialize
          target_type: mcp
          required_for_e2e: true
          required_capabilities:
            - mcp_runtime_probe
          blocked_by: []
          handoff_id: verify-mcp-initialize
```

- `id` は stable な一意値。命名規則は推奨するが、`branch`/`phase`/`target_type` は別フィールド。
- `blocked_by` は原因となる verification item ID 参照。
- `required_for_e2e: false` の item は E2E completion 判定に含めない。

### layer vocabulary

推奨セット（必須ではなく拡張可能）。

```text
choice / installer / cli / env / settings / generated_config / registration / discovery / runtime_consumer / activation / representative_operation / verification
```

### branch + layer mapping

Setup Contract は expected topology を宣言。audit で observed topology + discrepancy を生成。

---

## Complexity 判定

- `analyze-repo.sh`：既知の complexity trigger を事実として抽出し提示。
- trigger 数を機械的にスコアリングして確定しない。
- Agent：trigger + repository context から通常フロー / 強化フローを判断。
- 未知の同等ケースも強化対象にできる。
- User Ask：判断が曖昧、または強化フローで作業範囲・外部操作が大きく変わる場合のみ。

代表的な trigger：

- 複数レイヤーをまたぐ設定分岐
- 複数 config writer / runtime consumer
- Skill / Plugin 等の install または registration
- Agent/client 側 discovery が必要
- client reload / new session が必要
- MCP runtime
- 外部サービスや Gateway
- Hook / event delivery
- setup 中の secret-bearing artifact
- 複数の既存 setup asset にまたがる setup contract

---

## Target Type 識別

優先順位：

1. 既存の `agent-setup-protocol` / Setup Contract / README / repository policy
2. 既知の manifest / config / file pattern からの推定
3. Agent 判断
4. 作業範囲に影響する曖昧さがあれば Ask

- 複数 target は `Skill + MCP` のように複数保持。
- 未知 type は `other/custom` として generic E2E chain から構成。

---

## Cross-layer Audit

### 新 script: `audit-contract.sh`

```bash
bash audit-contract.sh <repo-path> [--contract <path>]
```

責務：静的・構造的整合性。`verify-setup.sh` とは分離。

### 処理

1. Setup Contract YAML frontmatter を parse
2. Contract discovery status を判定
3. `configuration_branches[*].layers` の参照先を検索
4. `installation` / `registration` / `discovery` / `activation` の参照先を検証
5. `verification` 内の `blocked_by` ID 存在確認
6. 全 schema 領域からの `handoff_id` 参照整合性確認
7. `required_capabilities` が schema 上妥当・参照可能か確認（availability は判定しない）
8. 結果を JSON / Markdown 両形式で出力

### Contract discovery

```yaml
contract_discovery:
  status: found | not_found | ambiguous
  path: docs/agent-setup-contract.md
  source: explicit | repository_declared | marker_scan
```

- `not_found`: audit finding は生成せず、Setup Contract extraction に戻す
- `ambiguous`: Agent semantic review に戻す
- 通常 Markdown を Contract と誤認しない

### finding state

```yaml
finding_state: confirmed | candidate | unresolved
```

- `confirmed`: evidence だけで静的不整合の存在が確定
- `candidate`: heuristic evidence あり
- `unresolved`: evidence は取得済みだが semantic review が必要

`confirmed` でも自動修正は行わない。gap classification と修正方針は Agent 判断。

### gap classification

- `documentation_gap`
- `bootstrap_gap`
- `configuration_gap`
- `runtime_gap`
- `registration/discovery_gap`
- `activation/verification_gap`
- `out_of_scope`

---

## Capability Matrix

### 2層構造

```text
generic Agent capability
        ↓ prerequisite
setup-specific capability
        ↓ default profile
target type
        ↓ override/refinement
Setup Contract required_capabilities
        ↓
verification plan / handoff
```

### 既存 `agent-capability-matrix.md`

generic capability の availability source of truth は維持。`setup-capability-matrix.md` は availability を再定義しない。

### 新 `setup-capability-matrix.md`

setup-specific capability 定義と target type ごとの default profile。

```yaml
capabilities:
  mcp_runtime_probe:
    description: "Start/interact with an MCP server runtime"
    generic_prerequisites:
      candidates:
        - command_execution
      note: "Availability is determined by concrete probe, not prerequisite AND"
```

default profile は「典型的に必要になる capability のヒント」として `commonly_used` で表現。

```yaml
default_profiles:
  skill:
    commonly_used:
      - target_installation
      - agent_discovery_probe
      - representative_activation_probe
```

### capability assessment

Verification Report において各 required capability を評価。

```yaml
capability_assessment:
  mcp_runtime_probe:
    status: available | unavailable | unknown
    reason: "..."
    evidence: []
```

`available` / `unavailable` / `unknown` は generic prerequisite から自動導出しない。

---

## Verification Status

### 個別 item

```yaml
items:
  - id: mcp.initialize
    status: verified | not_verified | not_applicable
    reason: "..."
    handoff_id: ...
    next_step: "..."
    required_evidence: []
```

### E2E status 派生

verification item に `required_for_e2e: true | false` を持たせる。

```yaml
targets:
  mcp_main:
    target_type: mcp
    e2e_status: not_verified
    e2e_status_reason: "required item mcp.initialize is not_verified"
```

派生規則：

- `not_applicable`: `required_for_e2e: true` かつ `not_applicable` でない item が存在しない
- `verified`: すべての `required_for_e2e: true` かつ `not_applicable` でない item が `verified`
- `not_verified`: それ以外

`blocked_by` は状態伝播ではなく「その item を現在実行できない理由」に留める。

---

## Handoff

### 定義（Setup Contract 側）

```yaml
handoffs:
  verify-mcp-initialize:
    actor: agent | user | external
    action: "Start MCP server and send initialize request"
    prerequisites: []
    expected_outcome: "MCP server returns initialize response"
    required_evidence:
      - type: command_output
        summary: "initialize response"
```

### 実行記録（Verification Report 側）

```yaml
handoffs:
  - handoff_id: verify-mcp-initialize
    verification_item_id: mcp.initialize
    actor: user
    status: pending | completed | failed
    evidence: []
    evaluation_result: pending | success | failure | needs_review
```

### 評価フロー

```text
handoff completed
→ evidence acquired
→ required_evidence に照らして評価
→ evaluation_result
→ verification item status
```

`evaluation_result: success` = required evidence が verification condition を満たした。

evidence は種類・要約・参照先のみ。全文は frontmatter に埋め込まず、秘密・credential を含む可能性がある場合は `artifact_secret_lifecycle` の対象にする。

---

## Dry-run 不変条件

### 3層 defense-in-depth

1. **ポリシー**: SKILL.md / references で禁止事項を明文化
2. **classifier**: dry-run 中は known-safe のみ実行
3. **snapshot**: classifier をすり抜けたローカル mutation を検知

### classifier 規則（dry-run）

```text
known-safe (read-only) → execute
known-mutating → not_executed
unknown → not_executed
```

- `local-only` / `idempotent` だけを safe にはしない。
- ephemeral operation を実行する場合は、事前に cleanup procedure と mutation surface を定義し、実行後に cleanup + snapshot verification を必須とする。
- cleanup または snapshot verification に失敗した場合は `dry_run_invariant_violation` として dry-run verification 自体を失敗扱い。

### scoped snapshot

- 対象は Setup Contract / repository evidence から得た具体的な mutation surface のみ。
- snapshot は metadata/hash を temporary directory に保持。secret 内容は含まない。
- 終了時に cleanup。
- `external_effects` に `mutation_surfaces` を追加して可視化する。

---

## Target-Specific E2E Verification

### Skill

```text
install / register → agent_discovery → representative_activation
```

- `representative_activation_probe` available かつ安全なら representative prompt で activation 確認。
- 不可能なら `discovery: verified`, `activation: not_verified` に分離。

### MCP

```text
runtime_start → initialize → tool_discovery → representative_tool_call
```

- 特定 tool 名は generic skill に固定しない。
- Setup Contract に基づいて安全な代表 tool を選択。
- read/write 双方が本質的なら一時データで検証。

### Plugin / Hook / CLI / Service

Setup Contract から generic chain を構成。

```text
installation / registration → discovery / readiness → activation / invocation → representative observable outcome
```

---

## Regression Evidence / TDD

- 導入先 repository 側に回帰テストが原則。
- 形式は repo の既存テスト文化を優先。unit / integration / CI smoke / prompt-config generation test 等。
- skill 自身の script 変更は skill 側の script test で担保。
- `evals.json` 拡張は P2 対象外。
- 自動化不能な場合は「自動化できない理由 / 再現方法 / 修正後の検証方法 / 結果」を記録し、その箇所を完全 Verified 扱いにしない。

---

## 非機能要件

### 非破壊性

- 既存の manual setup、CI、Agent config、user-local config、unrelated working tree changes を破壊しない。
- `audit-contract.sh` は完全 read-only。

### 後方互換性

- 新 workflow は既存の simple-repo path を変えない。
- trigger がなければ標準 workflow のまま。

### 適応性

- 単純な repository に heavyweight verification を無条件で要求しない。

### 検証の正確性

- 実行・観測していない verification を成功と報告しない。
- 「install 済み」と「実際に利用可能」を区別する。

---

## 重要な境界 contract

| 項目 | Spec 1 で確定 | Spec 2 で利用 |
|---|---|---|
| Setup Contract schema | YAML frontmatter キー/構造 | verification planner / executor の入力 |
| verification item ID | stable ID、命名規則推奨 | `blocked_by` 参照 |
| capability requirement | verification item の `required_capabilities` | capability assessment → verification execution 可否 |
| handoff definition | handoff ID + handoff contract | handoff 選択 / 実行記録 / evidence evaluation |
| handoff ID | Contract 内で定義 | report 内で参照 |
| audit report schema | `observed_topology`, `discrepancy`, `finding_state` | verification 計画の入力 |
| layer vocabulary | 推奨セット | target-specific phase 設計の参考 |
| external mutation surfaces | `external_effects.mutation_surfaces` | scoped snapshot の対象 |

---

## 次のステップ

本設計の承認後、以下を順に作成する。

1. Implementation Plan 1（Spec 1）
2. Implementation Plan 2（Spec 2）
3. Integration checkpoint 定義

各計画は本上位設計と両詳細 spec に基づき、`writing-plans` skill で作成する。

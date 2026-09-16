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
| **Audit Report** | observed static topology、discrepancies | `audit-contract.sh` + Agent semantic review |
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

### Setup Contract v1 規範 schema

YAML frontmatter は唯一の機械可読 contract である。本文は説明専用であり、監査・実行の入力として解釈しない。値が `null` の field は存在しない field と同じであり、required field に `null` は使用できない。すべての path は target repository root 基準の正規化済み相対 path とし、絶対 path、`..`、symbolic link を経由する repository 外への参照は schema error とする。

| Top-level key | 必須 | 型 / cardinality | 規範的意味 |
|---|---|---|---|
| `setup_contract_schema_version` | はい | integer、値は `1` | schema version。ほかの値は schema error。 |
| `setup_intent` | はい | non-empty string | setup の目的。機械的な分岐には使用しない。 |
| `setup_target` | はい | stable target ID を key にする non-empty map | target の canonical source と runtime を定義する。 |
| `complexity_triggers` | はい | list。空 list 可 | `{id, evidence, note}`。`id` は contract 内で一意。 |
| `configuration_branches` | はい | non-empty list | `{id, layers}`。`id` は stable かつ一意。 |
| `installation` / `registration` / `discovery` / `activation` | はい | target ID を key にする map。各値は list、空 list 可 | target phase ごとの静的 reference を定義する。 |
| `verification` | はい | `{targets: map}` | verification item と probe 定義を保持する。 |
| `handoffs` | はい | handoff ID を key にする map。空 map 可 | human/Agent/external actor へ渡す操作の定義。 |
| `external_effects` | はい | `{mutation_surfaces: list}` | persistent mutation scope と snapshot 変換規則。 |

`setup_target.<target_id>` は次の map である。`target_id` は `[a-z][a-z0-9_-]*` に一致し、contract 内の target reference はこの ID を使用する。

| Field | 必須 | 型 / 値 | 意味 |
|---|---|---|---|
| `target_type` | はい | `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, `other/custom` | target-specific probe profile を選ぶ discriminator。 |
| `canonical_source` | はい | `{kind, value, ref_mode, ref}` | `kind` は `repository_path`, `url`, `registry`, `external_resource`。`value` は kind に対応する canonical identifier。`ref_mode` は `immutable`, `mutable`, `not_applicable`。`ref` は `ref_mode` が `not_applicable` 以外なら必須、そうでなければ禁止。 |
| `runtime` | はい | `{mode, command, safety}` | `mode` は `process`, `in_process`, `agent_discovery`, `external_service`, `not_applicable`。`command` と `safety` は `process` のときだけ必須で、`command` は non-empty argv list、`safety` は `read_only|mutating|unknown`（`null` と列挙外は schema error）。`process` 以外では両方を禁止する。`safety` は作成者の宣言であり、実行許可ではない。 |

`configuration_branches[*]` は `{id, layers}` である。`layers` は non-empty list であり、各 layer は stable かつ branch 内で一意な `id` と `kind` を持つ。v1 の `kind` は closed enum であり、`choice`, `installer`, `cli`, `env`, `settings`, `generated_config`, `registration`, `discovery`, `runtime_consumer`, `activation`, `representative_operation`, `verification` のいずれかである。列挙されていない `kind` は schema error とし、v1 の実装は未知の locator shape や audit 規則を発明しない。機械的な locator は `kind` ごとに次の shape を使う。

| `kind` | 必須 field | 任意 field |
|---|---|---|
| `env` | `key` | `path` |
| `cli` | `option` | `path` |
| `generated_config` | `path`, `key` | なし |
| `runtime_consumer` | `path`, `symbol` | なし |
| `choice` / `installer` / `settings` / `registration` / `discovery` / `activation` / `representative_operation` / `verification` | `path` | `key`, `symbol` |

`path` は repository-relative path、`key` と `symbol` と `option` は non-empty string である。schema にない locator field は禁止する。これにより audit は layer の `kind` だけで検索規則を選択できる。

`installation`、`registration`、`discovery`、`activation` の各 phase map は target ID を key とし、値の list 要素は `{id, reference, verification_item_id, handoff_id}` である。`reference` は `{kind: path, path, symbol?}` または `{kind: external_resource, value}` のいずれかである。`verification_item_id` と `handoff_id` は省略可能だが、指定時は同じ target の item と contract の handoff をそれぞれ参照しなければならない。

`external_effects.mutation_surfaces[*]` は `{id, scope, kind, value, snapshot, cleanup_required}` である。`id` は一意、`scope` は `repository`, `user_local`, `global`, `external`、`kind` は `path`, `glob`, `external_resource`、`snapshot` は `required`, `not_supported`、`cleanup_required` は boolean とする。`repository` の `value` は repository-relative、`user_local` は `$HOME` relative、`global` は generic system identifier、`external` は external resource identifier である。`path` / `glob` かつ `snapshot: required` の surface は concrete path の metadata/hash list に展開する。`external_resource` と `snapshot: not_supported` は dry-run で実行できず、対応する operation は `not_executed` にする。

### Contract discovery protocol

Contract discovery は prose を推測しない。次の優先順位だけを実装する。

1. `--contract <repo-relative-path>` が指定された場合、その正規化済み path の regular file を唯一の contract とする。存在しない、repository 外、frontmatter marker 不正なら `contract_error`。
2. 指定がない場合、repository root の `AGENTS.md`、次に `README.md` を読む。各ファイルの独立した1行が `<!-- agent-setup-contract: path/to/contract.md -->` に完全一致するときだけ repository-declared marker とする。同じ優先ファイルに複数 marker、または両ファイルに異なる marker があれば `ambiguous`。
3. marker がない場合、`SETUP-CONTRACT.md` と `docs/**/*.md` だけを候補にする。先頭行が `---` の YAML frontmatter に integer `setup_contract_schema_version: 1` を持つ file だけを marker-scan candidate とする。候補が1件なら `found` / `marker_scan`、0件なら `not_found`、2件以上なら `ambiguous` とする。

発見結果は `{status, path, source}` であり、`status` は `found`, `not_found`, `ambiguous`, `contract_error`、`source` は `explicit`, `repository_declared`, `marker_scan`, `none` のいずれかである。`path` は `found` のときだけ存在する。

### verification item 定義

```yaml
verification:
  targets:
    mcp_main:
      target_type: mcp
      items:
        - id: mcp.initialize
          phase: initialize
          target_type: mcp
          required_for_e2e: true
          required_capabilities:
            - mcp_runtime_probe
          blocked_by: []
          handoff_id: verify-mcp-initialize
          probe:
            kind: mcp_request
            request: initialize
```

- `verification.targets` の key は `setup_target` の target ID と一致する。各 target の `target_type` は `setup_target.<target_id>.target_type` と一致する。
- `id` は target 内で stable かつ一意値。`branch`/`phase`/`target_type` は別 field である。
- `phase` は `installation`, `registration`, `discovery`, `activation`, `runtime_start`, `initialize`, `tool_discovery`, `representative_operation` のいずれかである。
- `blocked_by` は同一 target の verification item ID list。未知 ID、self reference、cycle は schema error。
- `required_capabilities` は optional list であり、指定時は null を禁止する。各要素は `[a-z][a-z0-9_-]*` に一致する unique な non-empty capability ID とする。同じ capability ID は複数 item から参照できる。Spec 1 はこの field の型・syntax・item 内重複だけを検証し、setup capability registry への存在確認と availability 判定は行わない。
- `probe` は required item に必須である。`kind` は `command`, `mcp_request`, `agent_action` のいずれか。`command` は non-empty `argv` list、`mcp_request` は `request: initialize|tool_discovery|representative_tool_call` を持つ。`initialize` と `tool_discovery` では `tool`, `arguments`, `safety`, `mutation_surface_id` を禁止し、`representative_tool_call` では `tool`、JSON object の `arguments`（空 object 可）、`safety: read_only|temporary_fixture` を必須とする。`safety: temporary_fixture` では `mutation_surface_id` も必須とし、`external_effects.mutation_surfaces` の `external` scope かつ `cleanup_required: true` の surface を参照する。`safety: read_only` では `mutation_surface_id` を禁止する。`agent_action` は `action: discovery|activation`、`adapter`、optional `prompt` を持つ。`adapter` は `{kind: command, argv: non-empty argv list, stdin: prompt|empty}` とし、shell 経由ではなく既存の公開された Agent mechanism を呼び出す。`stdin: prompt` のとき `prompt` は必須、`stdin: empty` のとき `prompt` は禁止する。adapter の exit 0 と観測可能な応答は `verified`、mechanism 不在は `capability_unavailable`、非 0 exit は `runtime_failure` とする。
- `required_for_e2e: false` の item は E2E completion 判定に含めない。

上記の `command` probe は `safety: read_only|mutating|unknown` を必須 field とし、`null` または列挙外の値は schema error とする。`temporary_fixture` は v1 の `command` probe では許可しない。`agent_action.adapter` も `safety: read_only|mutating|unknown` を必須 field とし、`null` または列挙外の値は schema error、`temporary_fixture` は v1 では許可しない。Command と adapter の safety 値は作成者による宣言であり、実行許可そのものではない。

P1 の現行 support boundary では、Policy v1 に具体的な public Agent discovery / activation seam を選定していないため、`agent_action` の discovery / activation adapter は自動実行しない。Contract の adapter、safety、prompt は handoff の評価材料として保持するが、宣言または capability の `available` だけで process start に進めてはならない。

MCP の `initialize` と `tool_discovery` は safety field を持たない固定の read-only protocol operation とする。MCP `representative_tool_call` の `safety` は既存の Contract-defined operation mode であり、`read_only` は `mutation_surface_id` なし、`temporary_fixture` は `external` scope、`snapshot: required`、`cleanup_required: true` の surface を必須とする。`temporary_fixture` は v1 schema では受理するが、P1 executor の自動実行対象ではない。normal verification の MCP representative call は `safety: read_only` に限り実行し、`temporary_fixture` は runtime process、operation、cleanup のいずれも開始せず `not_verified` / `safety_blocked`（定義済み handoff があればそれを出力）とする。dry-run の MCP chain は `runtime.command` を classification-only で評価し、`not_executed` とする。

### Probe safety contract

`probe.safety`、`agent_action.adapter.safety`、および `setup_target.<target_id>.runtime.safety` の実効 safety authority は `run-target-probes.sh` の固定 safety policy とする。Contract は任意の argv を `read_only` と宣言して実行許可に昇格させられない。

#### Probe Safety Policy v1

この policy は `command` probe、`agent_action.adapter`、および process mode の `setup_target.<target_id>.runtime.command` の argv に適用する。MCP の `initialize` / `tool_discovery` は固定 read-only、MCP `representative_tool_call` は Contract の operation mode を使い、protocol request 自体は argv classifier の対象にしない。MCP server process の start admission は `runtime.command` と `runtime.safety` に対して同じ classifier を使う。分類入力は Contract から得た argv token list と宣言された safety であり、prose、shell command string、通常 verification の `category` は入力にしない。

argv の正規化は次のとおり固定する。argv は空でない string list とし、`argv[0]` は `/` を含まない bare executable name でなければならない。absolute path、relative path、shell（`sh`、`bash`、`zsh`、`dash` など）、environment wrapper（`env`、`sudo`、`command`、`xargs` など）、環境変数展開、quote parsing、shell option は正規化しない。これらは registry に一致しないため `unknown` となる。argv token は変換せず、追加 token は許可しない。

known registry は P1 と既存の regression fixture に必要な最小集合とし、full argv の exact match だけを許可する。prefix match、executable + subcommand match、approved trailing args は v1 では使用しない。

| 実効分類 | canonical argv |
|---|---|
| `read_only` | `["node", "--version"]`、`["git", "status", "--porcelain"]`、`["agent-setup-mcp-stdio-readonly"]` |
| `mutating` | `["npm", "install"]` |

上記 registry のいずれにも exact match しない argv は `unknown` とする。known-mutating と known-read-only の双方に一致した場合は `mutating` を優先する。宣言された safety と実効分類が一致しない場合は safety mismatch として拒否し、一致していても実効分類が `mutating` または `unknown` なら実行しない。

P1 MCP stdio の safe runtime fixture は caller が target repository 外の `PATH` に用意する `agent-setup-mcp-stdio-readonly` executable とし、`runtime.command: ["agent-setup-mcp-stdio-readonly"]`、`runtime.safety: read_only` とする。stdin は newline-delimited JSON-RPC の `initialize`、`tools/list`、Contract 選択済み read-only tool call を順に受け、stdout は各 request に対応する observable response を返す。fixture は target repository、user-local settings、global config、external resource を変更しない。この exact argv は P1 の runtime-start fixture として registry に登録し、別の executable、wrapper、trailing args は同じ fixture を指していても `unknown` とする。

分類実装と registry の単一 owner は `run-target-probes.sh` とする。通常 verification は executor 内で command probe、supported runtime process、または adapter の process start 直前に同じ classifier を実行する。dry-run の admission は、`verify-setup.sh` が次の side-effect-free classification-only interface を呼び出して同じ結果を使う。`verify-setup.sh` は registry や matching 規則を複製しない。

```text
stdin:  {"argv":["node","--version"],"declared_safety":"read_only"}
command: bash run-target-probes.sh --classify-only
stdout: {"effective_safety":"read_only","declaration_matches":true}
```

`--classify-only` は入力 JSON の検証、分類、結果出力だけを行い、Contract、target repository、外部 resource を読み書きせず、target probe process または MCP runtime process を開始しない。入力が malformed の場合は exit 2 とし、target operation は開始しない。この classifier process の起動は target operation の process start には数えない。normal verification と dry-run は同一 argv に対して同じ `effective_safety` と `declaration_matches` を得なければならず、異なるのは実行判定だけである。

固定 safety policy は次の順で実効分類する。

1. known-mutating signature に一致する argv は `mutating` とする。
2. known-read-only allowlist に一致する argv は `read_only` とする。
3. どちらにも一致しない argv は `unknown` とする。

known-mutating と known-read-only の双方に一致した場合は `mutating` を優先する。Contract の宣言と実効分類が一致しない場合も safety mismatch として拒否する。`run-target-probes.sh` は command probe、supported runtime process、adapter の process start の直前にこの gate を最終適用し、`verify-setup.sh` は依存順序の orchestration と dry-run admission だけを担当する。orchestrator は safety gate を迂回して probe または MCP runtime を起動してはならない。

通常 verification と dry-run の実行判定は次のとおりである。

| 対象 / 実効 safety | 通常 verification | dry-run |
|---|---|---|
| command probe / adapter: `read_only` | 実行可 | `dry_run.decision: execute` として実行可 |
| MCP `runtime.command`: `read_only` | runtime process を起動して protocol operation を実行可 | classifier のみ実行し、`dry_run.decision: not_executed`。runtime process を開始しない |
| MCP `temporary_fixture` | runtime process、operation、cleanup のいずれも P1 では開始しない。`not_verified` / `safety_blocked` | `not_executed`。process を開始しない |
| command probe / adapter / MCP runtime: `mutating` | 実行不可。`not_verified` / `safety_blocked` | `not_executed`。process を開始しない |
| command probe / adapter / MCP runtime: `unknown` または safety mismatch | 実行不可。`not_verified` / `safety_blocked` | `not_executed`。process を開始しない |

MCP runtime の dry-run は、`runtime.command` の classification-only admission までに限定する。`runtime.safety: read_only` であっても server process、`initialize`、`tool_discovery`、representative call は開始せず、chain 全体を `dry_run.decision: not_executed` とする。normal verification の MCP runtime start は、`runtime.safety` と実効分類がともに `read_only` の場合だけ許可する。

`capability_assessment.status: available` は mechanism が存在し観測可能であることだけを示し、具体的 invocation が safe であることを示さない。Skill の `agent_discovery_probe` / `representative_activation_probe` が `available` でも、P1 の現行 boundary では自動 adapter process を開始せず、Contract-defined handoff を出力する。`verified` は safety gate 通過後に実行し、期待された evidence を得た結果だけに付与する。したがって `available`、invocation safe、target `verified` は独立した状態であり、available でも safety-blocked になり得るし、safe でも runtime failure により `not_verified` になり得る。

P1 の通常 verification は `external` resource を変更する operation を実行しない。`temporary_fixture` が指定された MCP representative call は runtime process、operation、cleanup のいずれも開始せず、`status: not_verified` / `error_category: safety_blocked` とする。該当 item に Contract-defined `handoff_id` があれば `status: pending` / `evaluation_result: needs_review` の handoff を出力し、なければ handoff を発明しない。宣言されていない persistent mutation、target repository、user-local settings、global config、external service の mutation も常に禁止する。

`cleanup_required` は Contract が cleanup の必要性を宣言する field であり、Contract に任意の cleanup command を記述して実行する仕組みではない。P1 では temporary fixture の operation も cleanup も自動実行しないため、temporary fixture に対応する transport、snapshot method、cleanup path は定義しない。将来の自動実行をこの文書の未定義部分から推測してはならず、P1 では unsupported probe mode として `safety_blocked` にする。

### layer vocabulary

Setup Contract v1 では次の closed enum を normative vocabulary とする。列挙外の `kind` は schema error であり、拡張は v1 の Contract では許可しない。新しい layer kind が必要になった場合は schema version または本設計を改訂する。

```text
choice / installer / cli / env / settings / generated_config / registration / discovery / runtime_consumer / activation / representative_operation / verification
```

### branch + layer mapping

Setup Contract は expected topology を宣言。audit で observed topology + discrepancies を生成。

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
bash audit-contract.sh [--contract <repo-relative-path>] \
  [--format json|markdown|both] [--output-dir <target-external-dir>] <repo-path>
```

責務：静的・構造的整合性。`verify-setup.sh` とは分離。

default は `--format json` で、JSON Audit Report を stdout に出す。`--format markdown` は同じ内容の Markdown を stdout に出す。`--format both` は `--output-dir` を必須とし、target repository 外の指定 directory に `audit-report.json` と `audit-report.md` を書き込む。target repository 内の output directory は usage error とする。Audit Report の top-level key は `contract_discovery`, `observed_topology`, `discrepancies`, `schema_errors`, `next_actions` に固定する。`discrepancies` は list であり、単数形 `discrepancy` は使用しない。

### 処理

1. Setup Contract YAML frontmatter を parse
2. Contract discovery status を判定
3. `configuration_branches[*].layers` の参照先を検索
4. `installation` / `registration` / `discovery` / `activation` の参照先を検証
5. `verification` 内の `blocked_by` ID 存在確認
6. 全 schema 領域からの `handoff_id` 参照整合性確認
7. `required_capabilities` の list shape、capability ID syntax、item 内重複を確認する。setup capability 定義への lookup と availability は判定しない
8. 結果を JSON / Markdown 両形式で出力

### Contract discovery

```yaml
contract_discovery:
  status: found | not_found | ambiguous | contract_error
  path: docs/agent-setup-contract.md
  source: explicit | repository_declared | marker_scan
```

- `not_found`: audit finding は生成せず、Setup Contract extraction に戻す
- `ambiguous`: Agent semantic review に戻す
- `contract_error`: malformed explicit path または malformed frontmatter。schema error として終了する
- 通常 Markdown を Contract と誤認しない

### finding state

```yaml
finding_state: confirmed | candidate | unresolved
```

- `confirmed`: evidence だけで静的不整合の存在が確定
- `candidate`: heuristic evidence あり
- `unresolved`: evidence は取得済みだが semantic review が必要

`confirmed` でも自動修正は行わない。gap classification と修正方針は Agent 判断。

Audit Report は finding ごとに `affected_target_ids` を必須で出力する。`schema_errors`、または target に紐づく `confirmed` finding がある場合、verification orchestrator は当該 target の probe を開始せず `audit_blocked` を記録する。`candidate` または `unresolved` finding は verification status を直接変更しないが、Agent semantic review が finding を解消するまで当該 target の E2E sign-off を `not_verified` に固定する。影響を受けない target の verification は継続できる。

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

setup-specific capability の定義と target type ごとの default profile の source of truth。Setup Contract は target が必要とする capability ID の source of truth であり、Spec 1 は matrix に依存せず ID の形だけを検証する。Spec 2 はこの matrix で定義を解決して capability を評価する。

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

`agent_discovery_probe` と `representative_activation_probe` は required capability の評価対象だが、capability が `available` でも P1 の Skill `agent_action` adapter を自動実行する許可にはならない。具体的な public Agent seam が Policy v1 に追加されるまで、discovery / activation item は `not_verified` / `safety_blocked` とし、Contract-defined handoff がある場合だけ pending handoff を出力する。

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

Spec 2 が `required_capabilities` の ID を `setup-capability-matrix.md` で解決できない場合は `unknown` とし、reason に定義未検出を記録する。対応する verification item は `not_verified` とし、Contract に定義された handoff がある場合だけ handoff を出力する。これは Spec 1 の schema error ではない。

### verification execution owner

`verify-setup.sh` は唯一の orchestration owner である。CLI parse、path-selection gate、Contract discovery、enhanced path の PyYAML preflight、audit gate 判定、capability assessment、report assembly、dry-run admission、exit status を所有する。target-specific operation は新しい `scripts/run-target-probes.sh` だけが実行する。`verify-setup.sh` は target ごとに依存順で verification item ID を指定して probe を起動し、item から導出した phase と probe output を Verification Report へ写す。probe は宣言されていない persistent mutation を行ってはならず、target repository、user-local settings、global config、external service を更新してはならない。P1 の Skill `agent_action` discovery / activation は自動実行せず、Contract-defined handoff 境界とする。P1 の MCP `temporary_fixture` は runtime process、operation、cleanup のいずれも自動実行せず `not_verified` / `safety_blocked`、dry-run では `not_executed` とする。

`run-target-probes.sh --contract <path> --target <target-id> --item <verification-item-id> --evidence-dir <external-temp-dir>` は JSON object を stdout に1件だけ出力する。`--item` は target 内で一意な verification item ID を指定し、phase はその item から導出する。v1 の executor interface に `--phase` selector は存在しない。分類共有のため、別モードとして `run-target-probes.sh --classify-only` は stdin の classification input を受け、`{effective_safety, declaration_matches}` を stdout に1件だけ出力する。shape は `{target_id, item_id, status, reason, evidence, error_category}`、`status` は `verified`, `not_verified`, `not_applicable`、`error_category` は `null`, `capability_unavailable`, `runtime_failure`, `audit_blocked`, `safety_blocked` のいずれかとする。server process の start/stop、timeout、runtime command / command probe / adapter の process start 直前の safety enforcement、P1 unsupported probe の拒否は probe owner が担う。MCP runtime command は `runtime.safety` を宣言として同じ classifier に渡し、effective safety が `read_only` で declaration が一致した場合だけ normal verification で start する。通常 verification の safety rejection または unsupported probe mode は `not_verified` / `safety_blocked` として返す。dry-run で抑止された operation または MCP runtime は target probe result を生成せず、orchestrator の `dry_run.decision: not_executed` に記録する。

P0 は Setup Contract audit、capability assessment、dry-run safety を実装する。P1 は `runtime.command` が Policy v1 の known `read_only` と一致する MCP stdio JSON-RPC の `initialize` / `tool_discovery` / `safety: read_only` の `representative_tool_call`、および CLI と Service の実効 safety が `read_only` の `command` probe を実装する。Skill の `agent_action` discovery / activation は P1 では自動実行せず、各 item の Contract-defined handoff 境界を出力する。MCP `temporary_fixture`、`mutating` / `unknown` command、safety を満たさない runtime command は自動実行せず、`safety_blocked`（dry-run では `not_executed`）とする。Plugin、Hook、`other/custom` は P1 では static phase verification と Contract-defined handoff のみを出力し、executor が未定義の probe を発明しない。

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

1. **ポリシー**: 本設計と SKILL.md / references で禁止事項を明文化
2. **classifier**: Probe Safety Policy v1 により dry-run 中は command probe / adapter の実効 safety が `read_only` の known-safe のみ実行し、MCP runtime は classification-only に限定
3. **snapshot**: classifier をすり抜けたローカル mutation を検知

### classifier 規則（dry-run）

```text
known-safe command / adapter (read-only) → execute
MCP runtime command (read-only) → not_executed; process を開始しない
temporary_fixture → not_executed
known-mutating → not_executed
unknown → not_executed
```

- `local-only` / `idempotent` だけを safe にはしない。
- 分類実装は `run-target-probes.sh` が所有する。通常 verification は process start 直前の内部 gate、dry-run は `--classify-only` interface による admission とし、registry と matching 規則を二重化しない。
- dry-run は temporary fixture、MCP runtime process、mutating operation、unknown operation を process start 前に抑止する。Contract に cleanup 要求と mutation surface があっても temporary fixture は実行しない。
- P1 の通常 verification では `temporary_fixture` を実行しない。対象 item は runtime process、operation、cleanup を開始せず `not_verified` / `safety_blocked` とし、Contract-defined handoff がある場合だけ handoff を出力する。
- dry-run の temporary storage cleanup、または read-only probe の snapshot verification に失敗した場合は `dry_run_invariant_violation` として dry-run verification 自体を失敗扱い。

### scoped snapshot

- 対象は Setup Contract / repository evidence から得た具体的な mutation surface のみ。
- snapshot は metadata/hash を temporary directory に保持。secret 内容は含まない。
- 終了時に cleanup。
- `external_effects` に `mutation_surfaces` を追加して可視化する。

### process-start I/O policy

`verify-setup.sh --dry-run` は target repository に対する最初の write より前から不変条件を適用する。`.agent-setup/` を含む target repository cache を作成・更新しない。analysis cache が必要な場合は `mktemp` で作成した target 外 directory にのみ保存し、stdout pipeline として consumer に渡す。before snapshot は Contract discovery と read-only parse の後、target repository への write より前に取得する。snapshot data、probe evidence、temporary fixture は target 外に置く。

`--report <path>` は dry-run でも使用できるが、正規化後に target repository 外でなければ usage error とする。report は明示的 artifact であり snapshot invariant の例外にはしない。temporary storage cleanup の失敗は `dry_run_invariant_violation` で exit 1 とし、終了後は `.agent-setup` を含む declared snapshot surface と repository working tree が unchanged でなければならない。

---

## Target-Specific E2E Verification

### Skill

```text
install / register → agent_discovery → representative_activation
```

- P1 では `agent_discovery_probe` と `representative_activation_probe` が available でも、具体的な public Agent seam が Policy v1 に選定されていないため adapter を自動実行しない。discovery / activation item は `status: not_verified` / `error_category: safety_blocked` とし、Contract-defined `handoff_id` がある場合だけ `status: pending` / `evaluation_result: needs_review` の handoff を出力する。handoff がない場合は発明しない。
- `agent_action` の schema は Contract の `adapter.argv`、`prompt`、stdin mode を保持するが、P1 executor は Agent CLI、argv、prompt を発明せず、adapter process を開始しない。将来 concrete seam を導入する場合も、既存の public Agent mechanism、exact argv、stdin contract、observable success condition、Policy v1 の safety authority を同時に設計更新する。

### MCP

```text
runtime_start → initialize → tool_discovery → representative_tool_call
```

- 特定 tool 名は generic skill に固定しない。
- Setup Contract の `tool`、`arguments`、`safety`、必要時の `mutation_surface_id` で安全な代表 tool と入力を明示する。executor は tools/list の結果から未指定の tool や入力を発明しない。
- `runtime.mode: process` の MCP は、`runtime.command` と `runtime.safety` を同じ Policy v1 classifier に通し、effective safety が `read_only` かつ declaration が一致した場合だけ normal verification で runtime process を起動する。P1 の safe runtime fixture は `runtime.command: ["agent-setup-mcp-stdio-readonly"]` とする。mutating、unknown、safety mismatch、process 以外の unsupported runtime は process start 前に拒否し、最初の MCP item を `not_verified` / `safety_blocked` とする。依存する item は開始しない。
- dry-run では runtime process を起動せず、`runtime.command` の classification-only admission だけを行い、MCP chain 全体を `dry_run.decision: not_executed` とする。`initialize` / `tool_discovery` が protocol-level read-only でも、server process の start admission を省略してはならない。
- read/write 双方が本質的、または external resource の操作が必要な場合でも、P1 は `temporary_fixture` の runtime process、representative tool call、cleanup のいずれも開始しない。対象 item は通常 verification では `not_verified` / `safety_blocked`、dry-run では `dry_run.decision: not_executed` とし、Contract-defined handoff がある場合だけ handoff を出力する。

### Plugin / Hook / CLI / Service

Setup Contract から generic chain を構成。

```text
installation / registration → discovery / readiness → activation / invocation → representative observable outcome
```

---

## CLI、output、error contract

`verify-setup.sh` の grammar は次に固定する。options は positional repository path より前に指定する。

```bash
bash verify-setup.sh [--dry-run] [--contract <repo-relative-path>] \
  [--report <target-external-markdown-path>] <repo-path>
```

`--report` 未指定時の stdout は既存互換の JSON verification plan である。既存の `commands`, `notes`, `makefile_targets` key は保持し、追加 key は additive とする。`--report` 指定時も stdout は同じ JSON plan とし、Verification Report は指定 path に YAML frontmatter + Markdown で書き込む。report path が target repository 内、parent が存在しない、または書込み不能なら usage error とする。

dry-run command decision vocabulary は `execute` と `not_executed` だけである。通常 plan の risk category は `safe` と `review` だけであり、両者を同じ field に混在させない。dry-run decision は `dry_run.decision`、通常 risk category は `category` に出力する。

通常 verification で required target が safety gate により `not_verified` になった場合は exit 4 とする。dry-run で安全ポリシーにより抑止した operation は `not_executed` であり、target runtime failure ではない。安全ポリシーを迂回した mutation または temporary storage / snapshot cleanup failure は、従来どおり `dry_run_invariant_violation` として exit 1 とする。

exit code は `0` = all required targets `verified` または `not_applicable`、`1` = unexpected operational failure または `dry_run_invariant_violation`、`2` = usage error / malformed Setup Contract、`3` = PyYAML dependency unavailable、`4` = audit gate、capability unavailable、safety blocked、または target runtime failure により required target が `not_verified` とする。Verification Report は exit 4 の場合も生成可能なら必ず出力し、`error_category` を `audit_blocked`, `capability_unavailable`, `runtime_failure`, `safety_blocked` のいずれかで記録する。

## Workflow path and parser dependency policy

### Path selection and dependency timing

`verify-setup.sh` の legacy simple path と enhanced Contract path の dependency 境界を次の順序に固定する。

1. CLI と path の形式を PyYAML なしで parse する。
2. 既存の trigger evidence、明示的 `--contract`、root `AGENTS.md` / `README.md` の standalone marker、marker-scan candidate の先頭 marker だけを read-only に確認する。この軽量 gate は YAML を parse せず、canonical な `contract_discovery` status を確定しない。
3. trigger も Contract indicator もない場合は legacy simple path を選択し、既存の標準 workflow をそのまま実行する。この path は PyYAML を要求せず、Contract parse と enhanced verification を行わない。
4. 明示的 `--contract`、repository-declared marker、marker-scan candidate、または Agent が enhanced path を選択した場合だけ enhanced path に入り、最初の YAML parse、Contract discovery、target write、snapshot より前に PyYAML preflight を行う。

simple path での PyYAML 不在は既存互換として扱い、enhanced path での PyYAML 不在だけを dependency error とする。

### Parser dependency policy

Setup Contract parser は runtime dependency の `PyYAML >=6.0,<7` である。`audit-contract.sh` は Contract を扱う全 invocation で、`verify-setup.sh` は enhanced path で、最初の Contract parse 前に availability を確認する。見つからなければ install を試みず、stderr に provisioning command と handoff を出して exit 3 にする。target repository への install、user-local install、dry-run 中の install は禁止する。

skill distribution は `skills/agent-driven-setup/requirements.txt` にこの range を記録する。skill caller は execution environment へ事前に dependency を provision し、CI は ephemeral runner で `python3 -m pip install -r skills/agent-driven-setup/requirements.txt` を実行してから script test を実行する。dependency がない local caller は explicit handoff を受け、target の verification は `not_verified` となる。

---

## Regression Evidence / TDD

- 導入先 repository 側に回帰テストが原則。
- 形式は repo の既存テスト文化を優先。unit / integration / CI smoke / prompt-config generation test 等。
- skill 自身の script 変更は skill 側の script test で担保。
- `evals.json` 拡張は P2 対象外。
- 自動化不能な場合は「自動化できない理由 / 再現方法 / 修正後の検証方法 / 結果」を記録し、その箇所を完全 Verified 扱いにしない。
- source behavior を変更する task は必ず RED test/fixture、RED command と期待 failure、minimum GREEN、GREEN command と期待 success、必要時だけ REFACTOR、再実行、commit の順で実施する。documentation-only task は runtime RED を要求しない。

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
| capability requirement | verification item の `required_capabilities` の ID・list shape・item 内一意性を検証。matrix lookup と availability は所有しない | `setup-capability-matrix.md` で定義を解決し、`available` / `unavailable` / `unknown` を assessment。unknown は item を `not_verified` にする |
| probe safety | `command.safety` / `agent_action.adapter.safety` / process runtime の `runtime.safety` の field shape と enum を検証。実効 safety の分類・実行許可は所有しない | Design の Probe Safety Policy v1 を `run-target-probes.sh` が唯一実装し、command / supported runtime / adapter の通常 start 前に最終 gate、dry-run は `--classify-only` で同じ分類を利用する。Skill `agent_action` は P1 では自動実行せず handoff 境界とする。通常の拒否は `not_verified` / `safety_blocked`、dry-run の拒否は `not_executed` |
| handoff definition | handoff ID + handoff contract | handoff 選択 / 実行記録 / evidence evaluation |
| handoff ID | Contract 内で定義 | report 内で参照 |
| audit report schema | `observed_topology`, `discrepancies`, `finding_state`, `affected_target_ids` | verification 計画の入力 |
| layer vocabulary | v1 closed enum と locator shape | target-specific phase 設計の入力。列挙外 kind は扱わない |
| external mutation surfaces | `external_effects.mutation_surfaces` | Contract-visible scoped snapshot metadata。P1 executor は external resource を操作せず、`temporary_fixture` を自動実行しない |

---

## 次のステップ

本設計の承認後、以下を順に作成する。

1. Implementation Plan 1（Spec 1）
2. Implementation Plan 2（Spec 2）
3. Integration checkpoint 定義

各計画は本上位設計と両詳細 spec に基づき、`writing-plans` skill で作成する。

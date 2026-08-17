# Temporary Credential Agent Skill 要件定義書

- **文書名**: Temporary Credential Agent Skill 要件定義書
- **対象ツール名**: Temporary Credential Agent Skill
- **バージョン**: 1.0
- **作成日**: 2026-08-16
- **ステータス**: 確定

## 1. 背景・目的

### 現状

AIエージェントにAWS、Cloudflare、Grafana、HCP Terraform等のクラウドサービスを調査・設定させる場合、各サービスのAPI Credentialが必要になる。

長期利用可能な高権限CredentialをAIエージェントへ直接渡す方式では、モデルコンテキスト、ログ、コマンド出力、子プロセス等へのCredential漏えい、および必要以上の権限による誤操作のリスクがある。

一方、AIエージェントによる調査・設定を実用的にするためには、作業の都度、人間がCredentialを手作業で生成・設定・削除する運用は避けたい。

### 解決したい課題

- AIエージェントに長期Credentialを開示せず、必要なクラウドサービスへアクセスさせる。
- 調査ではReadonly、変更作業では承認済みのWritableという明確な権限境界を設ける。
- 作業対象と操作内容に応じた最小権限Credentialを一時的に発行する。
- 作業終了後または異常終了後に、一時Credentialが残存し続けないようにする。
- Credentialの秘密値をAIモデル、監査ログ、通常のコマンド出力へ露出させない。
- 一時Credentialの発行、利用、承認、失効を追跡可能にする。

### 開発目的

Bitwarden Secrets Managerに安全に保管された親Credentialを利用し、汎用AIエージェントからの依頼に応じて、対象サービス固有の一時Credentialを最小権限で発行し、そのCredentialを秘匿したまま許可された調査・設定操作を実行し、終了時に失効させるスキルを提供する。

### 成功条件

1. Readonly作業では、人間による都度承認なしで最小権限の一時Credentialを発行・利用できる。
2. Writable作業では、人間の明示承認が存在する場合のみ一時Credentialを発行できる。
3. 親Credentialおよび `BWS_ACCESS_TOKEN` がAIモデルまたは通常の作業プロセスへ露出しない。
4. 一時Credentialの秘密値もAIモデルへ返却されない。
5. 作業成功・失敗・タイムアウト・中断のいずれでも失効処理が実行される。
6. 異常終了により即時失効処理が実行できなかった場合でも、サービス側TTLまたは後続の残存Credential回収によってCredentialを無効化できる。
7. ReadonlyからWritableへの暗黙の権限昇格が発生しない。
8. 一時Credentialの発行、対象、権限、承認、利用、失効結果を秘密値なしで監査できる。
9. AWS、Cloudflare、Grafana Cloud、self-hosted Grafana、HCP Terraformで主要フローを利用できる。

---

## 2. 対象ユーザー

### ユーザー種別

#### AIエージェント
本スキルを呼び出して、クラウドサービスの調査または設定を実行する主体。

#### 人間の利用者
AIエージェントへ作業を依頼し、必要に応じてWritable操作を承認する主体。

#### 管理者
Bitwarden、親Credential、対象環境、サービス側のRole・権限・Service Account等を事前設定する主体。

### 特徴、権限、前提知識

- AIエージェントは親Credentialを直接取得できない。
- AIエージェントは `BWS_ACCESS_TOKEN` を取得できない。
- AIエージェントは一時Credentialの秘密値も原則取得できない。
- AIエージェントは登録された対象に対するReadonly操作を自律実行できる。
- Writable操作には人間の明示承認が必要である。
- 管理者は対象サービスのCredential・IAM・RBAC等を設定できる知識と権限を持つことを前提とする。

### 利用環境

- Linux: Must
- macOS: Must
- Windows: Should
- 特定のAIエージェント製品には依存しない。
- AIエージェントから呼び出せる汎用スキルとして利用する。
- AIエージェント製品固有の組み込み方法は本要件の対象外とする。

### 主なニーズ

- 調査を安全にAIへ任せたい。
- 必要な場合のみ、明示承認して設定変更もAIへ任せたい。
- 長期CredentialをAIへ渡したくない。
- 作業後のCredential削除忘れを防ぎたい。
- 誰が、何の目的で、どの範囲のCredentialを利用したか追跡したい。

---

## 3. 利用シナリオ

### SC-001 Readonlyによる調査

**利用者:** AIエージェント  
**開始条件:** 対象環境が事前登録され、Readonly用一時Credentialを発行可能である。

**基本フロー:**

1. AIエージェントが対象サービス、対象環境、作業内容、対象リソースを指定する。
2. 権限種別が省略されている場合、Readonlyとして扱う。
3. スキルが要求内容から必要な最小権限を決定する。
4. 隔離されたCredential発行処理がBitwarden Secrets Managerから親Credentialを取得する。
5. サービス側で対象作業に必要なReadonly一時Credentialを発行する。
6. 一時CredentialをAIモデルへ返却せず、許可された対象サービスCLI/APIの子プロセスへ注入する。
7. 調査を実行する。
8. AIエージェントへ調査結果のみを返却する。
9. 一時Credentialを失効または削除する。
10. 実行結果と失効結果を監査ログへ記録する。

**期待結果:** AIエージェントは秘密値を知ることなく対象サービスを調査でき、一時Credentialは終了後に利用不能になる。

### SC-002 Writableによる設定変更

**利用者:** AIエージェント、人間の利用者  
**開始条件:** 対象環境が事前登録され、要求された変更が禁止操作に該当しない。

**基本フロー:**

1. AIエージェントが設定変更を要求する。
2. スキルがサービス、対象リソース、予定操作、必要権限、有効期間を提示して人間の承認を要求する。
3. 人間が当該作業セッションについて明示承認する。
4. スキルが承認内容を超えない最小権限のWritable一時Credentialを発行する。
5. Credentialを秘匿した状態で許可されたCLI/API操作を実行する。
6. 結果をAIエージェントへ返却する。
7. Credentialを失効または削除する。
8. 要求、承認、操作、結果、失効結果を監査する。

**期待結果:** 承認された対象・操作範囲内の変更だけが実行され、Credentialは作業後に利用不能になる。

### SC-003 Readonlyでは実行不能な操作

**利用者:** AIエージェント  
**開始条件:** Readonlyセッション中にWrite権限が必要になる。

**基本フロー:**

1. Readonly権限では操作できないことを検出する。
2. より強いCredentialへ自動的に切り替えない。
3. 必要なWritable操作、対象、権限を提示する。
4. 人間の新規承認を要求する。
5. 承認されなければ処理を終了する。

**期待結果:** ReadonlyからWritableへの暗黙の権限昇格が発生しない。

### SC-004 作業失敗・タイムアウト

**利用者:** AIエージェント  
**開始条件:** 一時Credential発行後に作業が失敗、タイムアウトまたは中断する。

**基本フロー:**

1. 作業を失敗として記録する。
2. 作業結果に関係なくCredential失効を試行する。
3. 失効成功時は失効済みとして記録する。
4. 失効失敗時はCredential残存を重大エラーとして記録する。
5. 残存Credential情報を永続管理対象に登録する。

**期待結果:** 作業失敗によってCredentialの後処理が省略されない。

### SC-005 プロセス強制終了後の回収

**利用者:** 次回起動したスキルまたはCredential管理処理  
**開始条件:** 前回処理が強制終了し、未失効の可能性があるCredential記録が存在する。

**基本フロー:**

1. 永続化された未失効Credential情報を読み込む。
2. Credentialの状態をサービス側で確認する。
3. まだ有効な場合は失効を試行する。
4. 結果を監査ログへ記録する。
5. 無効化を確認できた記録を未失効管理対象から解除する。

**期待結果:** プロセス異常終了によって残存したCredentialを後続処理で回収できる。

---

## 4. スコープ

### 今回の対象

#### Must対応サービス

- AWS
- Cloudflare
- Grafana Cloud
- self-hosted Grafana
- HCP Terraform

#### Should対応サービス

- GitHub
- Google Cloud
- Microsoft Azure
- Datadog
- Vercel
- Supabase

#### 共通機能

- Bitwarden Secrets Manager CLI (`bws`) を利用した親Credential取得
- Readonly / Writable権限モデル
- 作業内容に基づく最小権限化
- 一時Credential発行
- TTL設定
- 許可されたCLI/API経由での作業実行
- 作業終了時のCredential失効
- 異常終了後の残存Credential回収
- Writableの人間承認
- Credential値の秘匿
- 監査ログ
- 登録済み環境制限
- 危険操作の禁止

### 今回の対象外

- Bitwarden Password Manager CLI (`bw`)
- Bitwarden Projectの初期作成
- Bitwarden Machine Accountの初期作成
- `BWS_ACCESS_TOKEN` の初期発行
- 各サービスの親Credentialの初期作成
- AWS Role、Cloudflare権限、Grafana Service Account/RBAC、HCP Terraform Team等の初期設定
- 新規対象Account、Organization、Zone、Stack、Workspace等の初期登録
- AIエージェント製品固有の組み込み方法
- 任意のシェルコマンド実行
- Credential秘密値のAIエージェントへの返却
- Account / Organization / Project等の削除
- IAM / RBAC / メンバー権限変更
- Billing・支払方法変更
- Secret / Password / Private Key値の取得
- セキュリティ機構の無効化
- 監査ログの無効化
- Credential発行基盤自体の設定変更
- Writable Credentialを利用した別Credential・ユーザー・Role・Service Accountの作成または権限拡大
- 外部SIEMへの監査ログ転送
- 実装アーキテクチャ、フレームワーク、ライブラリの選定

### 将来候補

- Should対象サービスのMust化
- その他クラウド/SaaSへの対応
- WindowsのMust化
- 外部SIEMまたは集中ログ基盤への監査ログ転送
- 外部監査基盤との連携

### 前提条件

- 管理者が対象環境を事前登録している。
- 対象サービス側で必要なCredential発行・失効権限が設定済みである。
- Bitwarden Secrets Managerが利用可能である。
- `bws` が実行可能である。
- `BWS_ACCESS_TOKEN` がAIエージェントから隔離された実行環境へ外部注入されている。
- Writable承認を必要とする環境では、人間による明示承認を識別できる呼び出し経路が存在する。

---

## 5. 機能要件

| 要件ID | 機能名 | 要件 | 優先度 | 根拠 | 対応する受入条件ID |
|---|---|---|---|---|---|
| FR-001 | 要求受付 | Credential利用要求として、対象サービス、対象環境、作業内容、対象リソース、Readonly/Writable、有効期間を受け付ける。Readonly/Writableおよび有効期間は省略可能とする。 | Must | 最小権限判定に必要 | AC-001 |
| FR-002 | デフォルト権限 | 権限種別が省略または不明確な要求はReadonlyとして扱う。 | Must | 暗黙の高権限利用防止 | AC-002 |
| FR-003 | デフォルトTTL | 有効期間が省略された場合、一時Credentialの要求有効期間を1時間とする。 | Must | 一時Credentialの長期残存防止 | AC-003 |
| FR-004 | 要求情報検証 | 最小権限を決定するための情報が不足している場合、Credentialを発行せず、不足情報を返す。 | Must | 過剰権限防止 | AC-004 |
| FR-005 | 登録済み環境制限 | 親Credentialを利用できる対象を事前登録されたAccount / Organization / Zone / Stack / Workspace等に限定する。 | Must | 任意の外部対象へのCredential利用防止 | AC-005 |
| FR-006 | 最小権限判定 | Readonly/Writableを権限上限とし、実際に発行するCredentialは要求された作業と対象リソースに必要な最小権限に限定する。 | Must | Least Privilege | AC-006 |
| FR-007 | 権限拡大禁止 | 要求した権限をサービス側で発行できない場合、より広い権限へ自動フォールバックしない。 | Must | 権限逸脱防止 | AC-007 |
| FR-008 | Readonly保証 | Readonly要求ではWrite権限を含むCredentialを発行しない。 | Must | 調査専用アクセス保証 | AC-008 |
| FR-009 | Writable承認 | Writable Credentialは人間による明示承認が確認できた場合のみ発行する。 | Must | 誤変更防止 | AC-009 |
| FR-010 | 承認スコープ | Writable承認は1作業セッションに限定し、サービス、対象リソース、許可操作、有効期間を固定する。 | Must | 承認の使い回し防止 | AC-010 |
| FR-011 | 再承認 | 承認済み範囲を超える対象、操作または権限が必要になった場合、新しい承認なしでは続行しない。 | Must | 権限拡張防止 | AC-011 |
| FR-012 | Bitwarden取得 | 親CredentialはBitwarden Secrets Manager CLI (`bws`) を利用して取得する。 | Must | ユーザー指定 | AC-012 |
| FR-013 | Bitwarden読取限定 | スキルが使用するMachine Accountは登録Projectに対して `Can read` を基本とし、スキルはSecret/Projectの作成・更新・削除系操作を実行しない。 | Must | Bitwarden権限最小化。Bitwarden公式仕様 | AC-012 |
| FR-014 | 親Credential用途限定 | 親Credentialは一時Credentialの発行、状態確認、失効にのみ利用し、通常の調査・設定処理には利用しない。 | Must | 親Credential隔離 | AC-013 |
| FR-015 | BWS Token隔離 | `BWS_ACCESS_TOKEN` はCredential発行処理だけが利用でき、AIモデルおよび通常の作業子プロセスから取得できないものとする。 | Must | Secret Zero保護 | AC-014 |
| FR-016 | 親Credential隔離 | Bitwardenから取得した親CredentialをAIモデルまたは通常の作業子プロセスへ渡さない。 | Must | 高権限Credential保護 | AC-015 |
| FR-017 | 一時Credential発行 | 対象サービスに応じたサービスネイティブの一時または失効可能Credentialを発行する。 | Must | 目的機能 | AC-016 |
| FR-018 | リソース制限 | サービスが対応している場合、Account / Role / Resource / Zone / Stack / Organization / Workspace等までCredentialの利用対象を限定する。 | Must | Least Privilege | AC-006 |
| FR-019 | サーバー側TTL | サービスがCredential有効期限をサポートする場合、サービス側に有効期限を設定する。 | Must | 異常終了対策 | AC-003 |
| FR-020 | TTL非対応時処理 | サービス側でCredential TTLを設定できない場合、作成時刻・作業ID・Credential識別子を記録し、終了時削除および残存回収の対象とする。 | Must | TTL非対応サービス対策 | AC-017 |
| FR-021 | Credential非返却 | 一時Credentialの秘密値をAIモデルへ返却しない。 | Must | Credential漏えい防止 | AC-018 |
| FR-022 | 限定実行 | 一時Credentialは許可された対象サービスCLI/API操作を行う子プロセスまたは同等の隔離実行境界にのみ渡す。 | Must | 秘密値隔離 | AC-019 |
| FR-023 | 任意シェル禁止 | Credentialを保持する実行境界では任意シェルコマンドを実行させず、サービスごとに許可された実行経路のみ利用する。 | Must | Credential読み出し・外部送信防止 | AC-020 |
| FR-024 | 作業結果返却 | AIエージェントには秘密値を除去した作業結果、終了状態、必要なエラー情報を返す。 | Must | エージェント利用 | AC-018 |
| FR-025 | 正常時失効 | 作業終了後、有効期限前であっても発行した一時Credentialを速やかに失効または削除する。 | Must | Credential残存防止 | AC-021 |
| FR-026 | 異常時失効 | 作業失敗、タイムアウト、中断時にもCredential失効処理を実行する。 | Must | 異常系安全性 | AC-022 |
| FR-027 | 失効失敗 | Credential失効に失敗した場合、処理全体を正常完了扱いにせず、Credential残存の重大エラーとして報告する。 | Must | 残存Credential検知 | AC-023 |
| FR-028 | 残存Credential回収 | 起動時または後続実行時に未失効Credential記録を確認し、有効な残存Credentialの失効を再試行する。 | Must | 強制終了対策 | AC-024 |
| FR-029 | 一意識別 | 一時Credentialをサービス側で識別可能な場合、作業ID等を用いて当該作業とCredentialを追跡可能にする。 | Must | 回収・監査 | AC-024 |
| FR-030 | Fail Closed | Bitwarden、Credential発行API、権限判定等で安全性を確認できない場合、親Credentialへのフォールバックや権限拡大を行わず処理を中止する。 | Must | セキュリティ方針 | AC-025 |
| FR-031 | 通信再試行 | 一時的な通信障害についてのみ、安全に再試行可能な処理を再試行できる。 | Should | 外部API障害対応 | AC-026 |
| FR-032 | Writable不確定結果 | Writable操作の通信結果が不明で、操作が実行済みか判定できない場合、同じ変更を自動再実行せず「結果不確定」として返す。 | Must | 二重変更防止 | AC-027 |
| FR-033 | 危険操作禁止 | Writableであっても、スコープに列挙した高リスク操作を拒否する。 | Must | 安全性 | AC-028 |
| FR-034 | Credential発行能力分離 | 作業用Writable Credentialに、新規Credential、ユーザー、Role、Service Account等の作成または権限拡大能力を付与しない。 | Must | 権限連鎖防止 | AC-029 |
| FR-035 | 監査記録 | Credential要求、権限、対象、発行、承認、実行、失効について監査情報を記録する。 | Must | 追跡性 | AC-030 |
| FR-036 | 秘密値マスキング | stdout、stderr、エラー、監査ログ等に既知の親Credential、一時Credential、`BWS_ACCESS_TOKEN` が含まれる場合はAIまたは永続ログへ渡す前に除去またはマスキングする。 | Must | Credential漏えい防止 | AC-031 |
| FR-037 | サービス拡張 | 共通のReadonly/Writable、承認、隔離、失効、監査ポリシーを維持したまま新しい対象サービスを追加できることを要求する。 | Should | 将来サービス追加 | AC-032 |

---

## 6. 非機能要件

### 性能

| ID | 要件 |
|---|---|
| NFR-001 | スキル自身が不要な固定待機を挿入してはならない。外部サービスの応答待ちは設定可能なタイムアウトで制御できること。 |
| NFR-002 | 外部APIがタイムアウトした場合、作業を無期限に待機せず、安全な失効処理または残存Credential管理へ移行すること。固定のサービス応答SLAは定めない。 |

### 可用性

| ID | 要件 |
|---|---|
| NFR-003 | Bitwardenまたは対象サービスが利用不能な場合、安全性を低下させる代替Credentialへ切り替えないこと。 |
| NFR-004 | プロセス再起動後も未失効Credential情報を復元し、回収処理を再開できること。 |

### セキュリティ

| ID | 要件 |
|---|---|
| NFR-005 | `BWS_ACCESS_TOKEN`、親Credential、一時Credentialの秘密値をAIモデルのコンテキストへ含めないこと。 |
| NFR-006 | `BWS_ACCESS_TOKEN` を平文ファイルへ保存せず、AIエージェントから隔離された実行環境のSecretとして外部注入すること。 |
| NFR-007 | 親Credentialは原則としてCredentialの発行・確認・失効に必要な権限だけを持つこと。サービス仕様上それ以上の強い発行権限が必要な場合は高権限Credentialとして同等以上に隔離すること。 |
| NFR-008 | 秘密値を監査ログへ保存しないこと。 |
| NFR-009 | Credential秘密値を、モデル可視の出力、通常ログ、エラーメッセージ等へ露出させないこと。 |
| NFR-010 | `BWS_ACCESS_TOKEN` は有効期限を設定して管理し、期限切れ、漏えい疑い、運用者変更等の必要時に新規発行・旧Token失効を行えること。固定ローテーション日数は要求しない。 |

### プライバシー

| ID | 要件 |
|---|---|
| NFR-011 | 監査に不要な個人情報を収集しないこと。承認者情報を記録する場合は承認追跡に必要な識別情報に限定すること。 |

### アクセシビリティ

本ツールは汎用AIエージェントから機械的に利用されるスキルであり、独自GUIを初回要件としないため、個別のGUIアクセシビリティ要件は設定しない。

### 互換性

| ID | 要件 |
|---|---|
| NFR-012 | LinuxおよびmacOSで主要機能を利用可能であること。 |
| NFR-013 | Windows対応はShouldとする。 |
| NFR-014 | 特定のAIエージェント製品固有のプロトコルを前提条件としないこと。 |

### 拡張性

| ID | 要件 |
|---|---|
| NFR-015 | サービス追加時にも、共通のCredential隔離、Readonly/Writable、承認、TTL、失効、監査要件を変更せず適用できること。 |

### 保守性

| ID | 要件 |
|---|---|
| NFR-016 | サービス固有の権限・Credential仕様変更に対応できるよう、サービス固有ルールと共通セキュリティ要件を区別して管理できること。 |

### ログと監視

| ID | 要件 |
|---|---|
| NFR-017 | 監査ログはAIエージェントが通常操作で改ざん・削除できない専用領域へ構造化して保存すること。 |
| NFR-018 | Credential失効失敗を通常の作業失敗と区別できる重大エラーとして記録すること。 |
| NFR-019 | 監査ログの保持期間は90日以上とし、90日経過後は自動削除可能とすること。 |

### バックアップと復旧

| ID | 要件 |
|---|---|
| NFR-020 | 初回リリースでは監査ログ自体のバックアップを必須としない。 |
| NFR-021 | 未失効Credential追跡情報はプロセス異常終了後も失われないよう永続化すること。 |

### 運用性

| ID | 要件 |
|---|---|
| NFR-022 | Credential残存状態を、秘密値を表示せず管理者またはAIエージェントへ報告できること。 |
| NFR-023 | 初回リリースでは外部SIEM等の継続的な有料インフラを必須としないこと。 |

---

## 7. データ要件

| ID | 区分 | 要件 |
|---|---|---|
| DATA-001 | 入力データ | Credential要求には対象サービス、対象環境、作業内容、対象リソースを含める。権限種別と有効期間は省略可能とする。 |
| DATA-002 | 入力データ | Writable要求では、人間による承認情報をCredential発行前に取得する。 |
| DATA-003 | 出力データ | AIエージェントへ返すデータは作業結果、ステータス、エラー、監査用作業ID、Credential失効状態等とし、秘密値を含めない。 |
| DATA-004 | Bitwarden保存 | Bitwarden Project名は `<service>-<environment>` の規則を基本とする。例: `aws-prod`, `cloudflare-prod`。 |
| DATA-005 | Bitwarden保存 | Bitwarden Secret名には、そのCredentialを利用する際の環境変数名を使用する。 |
| DATA-006 | Bitwarden保存 | Bitwardenには長期利用する親Credentialと必要な登録設定情報を保存し、作業用一時Credentialは保存しない。 |
| DATA-007 | Bitwarden保存 | SecretにはAccount / Organization / Zone / Stack / Workspace等の対象を識別できるメタ情報を関連付ける。 |
| DATA-008 | Bitwarden保存 | 同一サービスでもproduction、staging等の環境が異なる場合はProjectを分離する。 |
| DATA-009 | 一時データ | 一時Credentialの秘密値は作業実行中のみ必要最小限の実行境界に存在し、恒久保存しない。 |
| DATA-010 | 監査データ | 監査ログには、実行日時、作業ID、サービス、対象環境、対象リソース、Readonly/Writable、要求権限、発行結果、承認者識別情報、Credential識別子、有効期限、操作結果、失効結果、失敗理由を記録する。 |
| DATA-011 | 監査データ | 監査ログに親Credential、一時Credential、`BWS_ACCESS_TOKEN` の秘密値を記録しない。 |
| DATA-012 | 未失効管理 | 未失効Credential情報としてサービス、作業ID、Credential識別子、対象、発行時刻、有効期限、最後の失効試行結果を永続化する。 |
| DATA-013 | 未失効管理 | 未失効Credential情報にCredentialの秘密値を保存しない。 |
| DATA-014 | データ量 | 想定データ量はCredential秘密値ではなく監査・追跡メタデータが中心であり、初回リリースでは特別な大容量処理を要求しない。 |
| DATA-015 | 保持期間 | 監査ログは90日以上保持する。 |
| DATA-016 | 保持期間 | 未失効Credential記録はCredentialの失効または期限切れを確認するまで保持し、その後は監査記録として90日保持可能とする。 |
| DATA-017 | 削除条件 | 監査ログは保持期間経過後に削除する。一時Credential秘密値は作業終了時に保持状態から除去する。 |
| DATA-018 | 機密区分 | `BWS_ACCESS_TOKEN` と親Credentialを最高機密、一時Credentialを機密、監査メタデータを内部情報として扱う。 |
| DATA-019 | バックアップ | 監査ログのバックアップは初回リリースでは要求しない。未失効Credential追跡情報は再起動後に復旧可能であることを要求する。 |
| DATA-020 | 移行要件 | 初回リリースで既存Credentialストアからの自動移行機能は要求しない。 |

---

## 8. 外部連携

| ID | 連携先 | 連携目的 | 送受信データ | 認証に関する要件 | 通信失敗時 | 外部制約・依存関係 |
|---|---|---|---|---|---|---|
| INT-001 | Bitwarden Secrets Manager | 親Credential取得 | Secret名、Project、親Credential値 | `bws` とMachine Account Access Tokenを使用。スキル用途では読取操作に限定 | Fail Closed。親Credentialを別手段へフォールバックしない | Machine Account、Project、Secretを管理者が事前設定 |
| INT-002 | AWS | 一時AWS Credential発行と作業実行 | 対象Role/Resource、Session条件、AWS API要求 | AWS STS等のサービスネイティブな一時Security Credentialを利用 | 発行不能なら中止。作業結果不確定時のWrite再実行は禁止 | AWS STSの期限・Role/Session Policyの制約に従う |
| INT-003 | Cloudflare | Scoped API Token発行と作業実行 | Account/Zone、Permission、TTL、API要求 | API Token発行能力を持つ隔離親Credentialを利用 | 発行・失効失敗を明示。権限拡大フォールバック禁止 | API Token Permission、Resource Scope、TTL等のCloudflare制約に従う |
| INT-004 | Grafana Cloud | Grafana Cloudの調査・設定 | Stack/Org、Scope、TTL、API要求 | 対象APIに適した失効可能Tokenを使用 | Fail Closed。失効失敗を残存Credentialとして管理 | Cloud Access Policy Token等の有効期限・権限制約に従う |
| INT-005 | self-hosted Grafana | Grafana Instanceの調査・設定 | Instance/Org、Role/Permission、TTL、API要求 | Service Account Token等の失効可能Credentialを利用 | Fail Closed。削除失敗時は残存管理 | 利用GrafanaバージョンのService Account/RBAC/TTL機能に依存 |
| INT-006 | HCP Terraform | Organization/Workspaceの調査・設定 | Team/Organization/Workspace、権限、期限、API要求 | 事前設定された権限境界に対応する期限付きTokenを利用 | Fail Closed。失効失敗を残存管理 | Team Token等のHCP Terraform権限・期限仕様に従う |
| INT-007 | 将来サービス | GitHub/GCP/Azure/Datadog/Vercel/Supabase等 | サービス固有 | 共通セキュリティ要件を満たす方式のみ追加 | 共通Fail Closed方針を適用 | サービスが最小権限・失効・追跡要件を満たせるか事前評価する |

### サービス別Credential原則

- **AWS:** STSによる一時Security Credentialを利用し、Role本来の権限を超えない範囲で作業対象に必要な権限へ制限する。
- **Cloudflare:** 対象Account/Zone、Permission、TTLを制限したAPI Tokenを利用する。
- **Grafana Cloud:** Cloud Access Policy Tokenまたは対象APIに適した失効可能Credentialを利用し、対象Stack/Organizationと権限を制限する。
- **self-hosted Grafana:** Service Account Token等を利用し、対象Organizationと権限を制限してTTLを設定する。
- **HCP Terraform:** 事前設定されたTeam等の権限境界に対応する期限付きTokenを利用し、必要なOrganization/Workspaceの範囲を超えないこと。

---

## 9. 制約

| ID | 種別 | 制約 |
|---|---|---|
| CON-001 | 技術 | Secret管理にはBitwarden Secrets Manager CLI (`bws`) を使用する。Password Manager CLI (`bw`) は使用しない。 |
| CON-002 | 技術 | AIエージェントは親Credentialおよび `BWS_ACCESS_TOKEN` を直接読み取れない実行境界でなければならない。 |
| CON-003 | 技術 | 一時CredentialもAIモデルへ直接返却しない。 |
| CON-004 | 技術 | Credentialを保持する実行境界から任意シェルコマンドを実行させない。 |
| CON-005 | 利用環境 | Linux/macOS対応をMust、Windows対応をShouldとする。 |
| CON-006 | 利用環境 | 操作対象は事前登録された環境に限定する。 |
| CON-007 | 権限 | 親Credentialは原則として子Credentialの発行・確認・失効専用とする。 |
| CON-008 | 権限 | サービス仕様上、Credential発行権限自体が広範な権限を意味する場合、その親Credentialは高権限Credentialとして隔離する。 |
| CON-009 | 権限 | ReadonlyからWritableへ自動昇格しない。 |
| CON-010 | 権限 | Writable承認を別セッション、別対象、別操作へ流用しない。 |
| CON-011 | 運用 | Bitwardenおよび各サービスの初期セットアップは人間の管理者が実施する。 |
| CON-012 | 運用 | 初回リリースでは監査ログをローカル専用領域に保存する。 |
| CON-013 | 予算 | Bitwardenおよび各対象サービスの既存契約範囲で利用し、本スキルのための継続的な追加有料インフラを必須としない。 |
| CON-014 | 納期 | 特定の納期制約は設定しない。 |
| CON-015 | 法務・規約 | 各対象サービスおよびBitwardenの利用規約、Credential/API利用条件に従う。 |
| CON-016 | 外部仕様 | Credential TTL、最小/最大有効期間、権限粒度、Token作成・削除API等は各サービスの現行仕様による。 |
| CON-017 | 高リスク操作 | Account/Org/Project削除、IAM/RBAC変更、Billing変更、Secret値取得、セキュリティ/監査無効化、Credential基盤変更は禁止する。 |
| CON-018 | 承認 | 呼び出し環境が人間の明示承認を識別できない場合、その環境ではWritable機能を利用不可とする。 |
| CON-019 | Credential期限 | サービス側が要求TTLを厳密に表現できない場合でも、要求より長期間有効なCredentialを黙って発行せず、サービス制約を適用またはエラーとして扱い、その事実を記録する。 |

---

## 10. 受入条件

### AC-001 要求受付

- **対応要件ID:** FR-001
- **前提条件:** AWS production環境が登録済み。
- **操作または入力:** AWS、production、対象リソース、調査内容を指定して要求する。
- **期待結果:** 要求が解析され、対象サービス・環境・作業・リソースが識別される。
- **合格基準:** 必須4項目が内部要求として識別され、Credential発行判断へ進める。

### AC-002 Readonlyデフォルト

- **対応要件ID:** FR-002
- **前提条件:** 権限種別を指定しない。
- **操作または入力:** 調査要求を送信する。
- **期待結果:** Readonlyとして処理される。
- **合格基準:** Writable Credentialが発行されない。

### AC-003 デフォルトTTL

- **対応要件ID:** FR-003, FR-019
- **前提条件:** サービスが1時間TTLをサポートする。
- **操作または入力:** 有効期間を省略してCredentialを要求する。
- **期待結果:** サービス側有効期限が発行時刻から1時間として要求される。
- **合格基準:** Credentialの有効期限が1時間となり、無期限Credentialにならない。

### AC-004 情報不足

- **対応要件ID:** FR-004
- **前提条件:** 複数の対象リソースが存在する。
- **操作または入力:** 対象を特定できない要求を行う。
- **期待結果:** Credentialを発行せず、不足情報を返す。
- **合格基準:** サービス側に新規Credentialが生成されない。

### AC-005 未登録対象拒否

- **対応要件ID:** FR-005
- **前提条件:** 登録されていないAccount IDを用意する。
- **操作または入力:** そのAccountへの作業を要求する。
- **期待結果:** 要求が拒否される。
- **合格基準:** Bitwarden親Credentialの利用および一時Credential発行が行われない。

### AC-006 最小権限

- **対応要件ID:** FR-006, FR-018
- **前提条件:** Cloudflareで特定ZoneのDNS Readのみを必要とする調査を行う。
- **操作または入力:** 当該ZoneのDNS調査を要求する。
- **期待結果:** 対象Zoneおよび必要なRead Permissionに限定されたCredentialが要求される。
- **合格基準:** 他ZoneまたはWrite権限がCredentialに含まれない。

### AC-007 自動権限拡大禁止

- **対応要件ID:** FR-007
- **前提条件:** 必要な細粒度Credentialを発行できない状態にする。
- **操作または入力:** 作業を要求する。
- **期待結果:** より広いCredentialへフォールバックせず失敗する。
- **合格基準:** 高権限Credentialが作業に利用されない。

### AC-008 Readonly保証

- **対応要件ID:** FR-008
- **前提条件:** Readonlyセッション。
- **操作または入力:** Writeを必要とする操作を要求する。
- **期待結果:** Write操作を実行しない。
- **合格基準:** 変更が発生せず、Writable承認が必要である旨が返る。

### AC-009 Writable承認必須

- **対応要件ID:** FR-009
- **前提条件:** 有効な人間承認が存在しない。
- **操作または入力:** Writable要求を送信する。
- **期待結果:** Credential発行前に停止する。
- **合格基準:** Writable Credentialが生成されない。

### AC-010 承認範囲固定

- **対応要件ID:** FR-010
- **前提条件:** 特定ZoneのDNS変更だけを承認する。
- **操作または入力:** 承認後にそのZoneのDNS変更を実行する。
- **期待結果:** 承認内容に一致する変更だけ実行可能となる。
- **合格基準:** 承認記録にサービス、対象、操作、有効期間が関連付けられている。

### AC-011 再承認

- **対応要件ID:** FR-011
- **前提条件:** Zone Aのみ承認済み。
- **操作または入力:** 同セッションでZone Bの変更を要求する。
- **期待結果:** 新規承認なしでは実行されない。
- **合格基準:** Zone Bに変更が発生しない。

### AC-012 Bitwarden読取

- **対応要件ID:** FR-012, FR-013
- **前提条件:** Machine Accountに対象Projectの `Can read` を設定する。
- **操作または入力:** 登録済み親Credentialを必要とする処理を実行する。
- **期待結果:** `bws` によりSecretを取得できる一方、スキルはSecret/Project変更操作を実行しない。
- **合格基準:** 必要Secretを取得でき、テスト期間中のBitwarden Secret/Project内容に変更が発生しない。

### AC-013 親Credential用途限定

- **対応要件ID:** FR-014
- **前提条件:** 親Credentialで子Credentialを発行できる。
- **操作または入力:** 通常の調査を実行する。
- **期待結果:** 調査処理では一時Credentialのみが使用される。
- **合格基準:** 対象サービスの作業要求に親Credentialが使用されていないことを実行記録で確認できる。

### AC-014 BWS Token隔離

- **対応要件ID:** FR-015
- **前提条件:** `BWS_ACCESS_TOKEN` を発行処理へ注入する。
- **操作または入力:** AIエージェントおよび作業子プロセスから環境・出力を確認する。
- **期待結果:** Token値を取得できない。
- **合格基準:** モデル出力、作業環境、監査ログにToken値が存在しない。

### AC-015 親Credential隔離

- **対応要件ID:** FR-016
- **前提条件:** 親CredentialをBitwardenに登録する。
- **操作または入力:** 一時Credentialを使った作業を実行する。
- **期待結果:** 親Credential値がAIまたは作業子プロセスに出現しない。
- **合格基準:** モデルコンテキスト、stdout/stderr、作業環境、監査ログから親Credential値を取得できない。

### AC-016 サービス別一時Credential

- **対応要件ID:** FR-017
- **前提条件:** Must対象5サービスのテスト環境が登録済み。
- **操作または入力:** 各サービスでReadonly Credentialを要求する。
- **期待結果:** 各サービスで失効可能または期限付きのCredentialが発行される。
- **合格基準:** AWS、Cloudflare、Grafana Cloud、self-hosted Grafana、HCP Terraformの各テストで発行・利用・失効フローが完了する。

### AC-017 TTL非対応回収

- **対応要件ID:** FR-020
- **前提条件:** サーバー側TTLを設定できないCredential発行方式を模擬する。
- **操作または入力:** Credentialを発行する。
- **期待結果:** 作業ID、Credential ID、作成時刻が未失効管理へ保存される。
- **合格基準:** 秘密値を保存せず、終了時の削除対象として識別できる。

### AC-018 Credential非返却

- **対応要件ID:** FR-021, FR-024
- **前提条件:** 一時Credentialを発行する。
- **操作または入力:** 調査を実行する。
- **期待結果:** AIへ調査結果のみ返る。
- **合格基準:** AI可視出力にCredential秘密値が存在しない。

### AC-019 限定注入

- **対応要件ID:** FR-022
- **前提条件:** 一時Credentialを発行する。
- **操作または入力:** 許可されたサービス操作を実行する。
- **期待結果:** Credentialは当該操作の実行境界にのみ存在する。
- **合格基準:** 親AIプロセスまたは無関係な子プロセスからCredential値を取得できない。

### AC-020 任意シェル禁止

- **対応要件ID:** FR-023
- **前提条件:** 一時Credentialを保持する作業セッション。
- **操作または入力:** 環境変数表示や任意外部送信を目的とした未許可コマンドを要求する。
- **期待結果:** コマンド実行前に拒否される。
- **合格基準:** 未許可プロセスが起動せず、Credentialが出力されない。

### AC-021 正常終了時失効

- **対応要件ID:** FR-025
- **前提条件:** 有効期限1時間のCredentialを発行する。
- **操作または入力:** 作業を正常終了する。
- **期待結果:** 1時間経過を待たずCredentialが失効される。
- **合格基準:** 終了後に同Credentialによる認証が成功しない。

### AC-022 異常終了時失効

- **対応要件ID:** FR-026
- **前提条件:** Credential発行済み。
- **操作または入力:** 作業を意図的に失敗またはタイムアウトさせる。
- **期待結果:** 失効処理が実行される。
- **合格基準:** 作業の成功可否にかかわらず失効API呼び出しが確認できる。

### AC-023 失効失敗

- **対応要件ID:** FR-027
- **前提条件:** 失効APIを意図的に失敗させる。
- **操作または入力:** 作業を終了する。
- **期待結果:** 正常完了扱いにならず、残存Credential重大エラーとなる。
- **合格基準:** エラー状態とCredential識別子が記録され、秘密値は記録されない。

### AC-024 強制終了後回収

- **対応要件ID:** FR-028, FR-029
- **前提条件:** Credential発行後、失効前にプロセスを強制終了する。
- **操作または入力:** スキルを再起動する。
- **期待結果:** 未失効記録が検出され、Credential状態確認と失効が試行される。
- **合格基準:** 残存Credentialが失効するか、失効不能状態が継続して重大エラーとして追跡される。

### AC-025 Fail Closed

- **対応要件ID:** FR-030
- **前提条件:** Bitwardenへのアクセスを失敗させる。
- **操作または入力:** Credentialを必要とする作業を要求する。
- **期待結果:** 処理が中止される。
- **合格基準:** キャッシュ済み高権限Credential等へのフォールバックが発生しない。

### AC-026 安全な通信再試行

- **対応要件ID:** FR-031
- **前提条件:** 読取APIに一時的な通信エラーを発生させる。
- **操作または入力:** Readonly処理を実行する。
- **期待結果:** 安全に再試行可能な処理のみ再試行される。
- **合格基準:** 再試行によってWrite操作やCredentialの重複発行が意図せず発生しない。

### AC-027 Writable結果不確定

- **対応要件ID:** FR-032
- **前提条件:** Writable APIが変更受付後に通信断する状況を模擬する。
- **操作または入力:** 変更操作を実行する。
- **期待結果:** 同一Writeを自動再送せず結果不確定として返す。
- **合格基準:** 同一変更APIが自動的に2回実行されない。

### AC-028 高リスク操作禁止

- **対応要件ID:** FR-033
- **前提条件:** Writable承認済み。
- **操作または入力:** IAM変更、Billing変更、Account削除等の禁止操作を要求する。
- **期待結果:** 承認済みであっても拒否する。
- **合格基準:** 対象サービスへ当該変更要求が送信されない。

### AC-029 Credential作成連鎖禁止

- **対応要件ID:** FR-034
- **前提条件:** 通常のWritable作業Credentialを発行する。
- **操作または入力:** そのCredentialを利用して別Credentialまたは権限主体の作成を試みる。
- **期待結果:** 権限不足またはスキル側拒否により実行できない。
- **合格基準:** 新規Credential、User、Role、Service Accountが作成されない。

### AC-030 監査ログ

- **対応要件ID:** FR-035
- **前提条件:** ReadonlyとWritable作業を各1回実行する。
- **操作または入力:** 監査ログを確認する。
- **期待結果:** 作業ID、日時、サービス、対象、権限、発行結果、承認情報、失効結果等が追跡できる。
- **合格基準:** DATA-010で規定した項目のうち当該作業に該当する全項目が存在する。

### AC-031 秘密値マスキング

- **対応要件ID:** FR-036
- **前提条件:** テストCredential値を出力に意図的に混入させる。
- **操作または入力:** stdout/stderrおよびエラー処理を実行する。
- **期待結果:** AI可視出力および永続監査ログでは値が除去またはマスキングされる。
- **合格基準:** 元Credentialの完全な秘密値がいずれの出力にも存在しない。

### AC-032 サービス追加可能性

- **対応要件ID:** FR-037, NFR-015
- **前提条件:** 既存Mustサービス以外のテスト用サービス連携を追加する。
- **操作または入力:** Readonly Credentialの発行・実行・失効フローを追加する。
- **期待結果:** 共通の承認、隔離、TTL、監査、失効ポリシーを変更せず利用できる。
- **合格基準:** 既存サービスの共通要件を弱める変更なしで追加サービスのフローを検証できる。

### AC-033 OS互換性

- **対応要件ID:** NFR-012, NFR-013
- **前提条件:** 同一の登録済みテスト環境を使用する。
- **操作または入力:** LinuxおよびmacOS上で主要なRead/Writeテストを実施する。
- **期待結果:** 両OSでMust機能が利用できる。
- **合格基準:** Linux/macOSの双方でAC-016、AC-021、AC-022が成功する。WindowsはShouldとして評価する。

### AC-034 タイムアウト安全性

- **対応要件ID:** NFR-001, NFR-002
- **前提条件:** 外部APIの応答を、設定されたタイムアウトを超えて停止させる。
- **操作または入力:** Credential利用処理を実行する。
- **期待結果:** 無期限待機せずタイムアウト扱いとなり、失効処理へ進む。
- **合格基準:** 設定したタイムアウト後に処理状態が遷移し、失効または残存管理が実行される。

### AC-035 監査ログ保持

- **対応要件ID:** NFR-017, NFR-019
- **前提条件:** 日付を制御できるテスト環境。
- **操作または入力:** 90日以内および保持期間経過後のログを用意する。
- **期待結果:** 保持期間中のログは参照可能で、期間経過ログは削除対象となる。
- **合格基準:** 90日未満の監査記録が自動削除されない。

### AC-036 BWS Access Token保護

- **対応要件ID:** NFR-006, NFR-010
- **前提条件:** `BWS_ACCESS_TOKEN` を外部Secretとして設定する。
- **操作または入力:** 実行環境の通常ファイル、モデル出力、作業子プロセスを検査する。
- **期待結果:** 平文Tokenが存在しない。
- **合格基準:** AIエージェントがToken値を取得できず、Token失効後はBitwarden Secretを取得できない。

### AC-037 未失効情報復旧

- **対応要件ID:** NFR-004, NFR-021
- **前提条件:** 未失効Credential記録を作成後、プロセスを終了する。
- **操作または入力:** 新しいプロセスとして再起動する。
- **期待結果:** 未失効情報が復元される。
- **合格基準:** Credential秘密値なしで対象Credentialを識別し、状態確認・失効処理を開始できる。

---

## 11. 未決事項

なし

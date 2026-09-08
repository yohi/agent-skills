# Temporary Credential Agent (管理者・開発者向けガイド)

AI エージェントが安全に一時クレデンシャル（Temporary Credentials）を取得・利用するためのポリシーと運用基盤の仕様です。
エージェント向けのプロンプト指示および認可ポリシーは [SKILL.md](SKILL.md) を参照してください。

---

## 1. 事前準備：Bitwarden Secrets Manager (BWS) のセットアップ

人間（インフラ・セキュリティ管理者）が事前に以下の設定を行います。

### (1) Project の作成
Bitwarden Secrets Manager の Web 管理画面で、Credential Broker 管理用のプロジェクトを作成します。
- **Project 名 例**: `agent-credential-broker`

### (2) Service Account と Access Token の作成
1. **Service Accounts** メニューから、Broker 実行用のサービスアカウント（例: `broker-runner`）を作成。
2. 作成した Project に対する権限を **Read-only**（読み取り専用）に設定。
3. 発行された `BWS_ACCESS_TOKEN` を Broker サーバー/実行コンテナの環境変数に設定。
   > ⚠️ **重要**: `BWS_ACCESS_TOKEN` は Broker の隔離環境でのみ使用し、AI エージェントの実行コンテキストには絶対に渡さないでください。

### (3) シークレット（親クレデンシャル）の登録フォーマット
BWS の Project 配下に、`<service>-<environment>` という命名規則でシークレットを登録します。

| シークレット名 (例) | 登録する Value (JSON 例) | 説明 |
|---|---|---|
| `aws-production` | `{"role_arn": "arn:aws:iam::123456789012:role/BrokerBaseRole", "external_id": "optional-id"}` | AWS STS AssumeRole 発行用の親ロール情報 |
| `cloudflare-production` | `{"api_token": "cf_parent_api_token_..."}` | 一時 API Token を作成・失効するための親 Token |
| `grafana-production` | `{"instance_url": "https://grafana.example.com", "admin_token": "glsa_..."}` | Service Account Token を作成・失効するための Admin Token |
| `terraform-production` | `{"org": "my-org", "admin_token": "..."}` | チームスコープの一時トークンを発行するための親 Token |

---

## 2. ディレクトリ構成

本スキルディレクトリは、エージェント用ファイルと評価用ファイルで構成されています。

```text
skills/temporary-credential-agent/
├── README.md                 # 本ドキュメント（人間・管理者向けガイド）
├── SKILL.md                  # AI エージェント用プロンプト・認可ポリシー定義
├── references/               # エージェントが実行時に必要に応じて参照する詳細仕様
│   ├── service-profiles.md   # サービスごとの許可操作・リソース境界定義
│   ├── audit-schema.md       # 監査ログスキーマおよびマスキング規約
│   └── evaluation-matrix.md  # 受け入れ検証シナリオ
└── evals/                    # スキル評価用テストケース
    └── evals.json            # 最小権限・TTL・秘密値隠蔽のテストケース
```

---

## 3. スキルの評価・テスト (Evals)

[evals/evals.json](evals/evals.json) に定義された各テストケースを通じて、AI エージェントが以下を正しく遵守できるかを検証します：

- **Readonly 既定動作**: 権限未指定時に自動で Readonly かつ 1時間 TTL を適用すること
- **変更操作の承認制**: Writable 操作の前に人間承認を要求し、無承認で実行しないこと
- **秘密情報の隠蔽**: 親トークン、一時トークン値、生のエラー出力をエージェント応答に含めないこと
- **失効と残存追跡**: タイムアウトや失敗時にも安全に失効処理と監査記録が行われること

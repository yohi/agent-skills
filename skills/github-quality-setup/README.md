# GitHub Quality & Security Setup (管理者・開発者向けガイド)

リポジトリに高品質・高セキュリティな CI/CD パイプライン（CodeRabbit, Dependabot, CodeQL, Semgrep, SonarCloud, Codecov, Trivy, Snyk）を一括構築・設定するためのスキルです。
エージェント向け指示は [SKILL.md](SKILL.md) を参照してください。

---

## 1. 事前準備：外部サービス登録と GitHub Secrets

選択したツールに応じて、人間（管理者）が事前に外部サービスでのアカウント登録および GitHub Secrets の登録を行います。

| ツール | 対象ファイル | 必要な Secrets / 事前準備 |
|---|---|---|
| **CodeRabbit** | `.coderabbit.yaml` | [CodeRabbit GitHub App](https://coderabbit.ai/) のリポジトリへのインストール |
| **Dependabot** | `.github/dependabot.yml` | 事前設定不要（GitHub 標準機能） |
| **CodeQL** | `.github/workflows/codeql.yml` | 事前設定不要（※GitHub Default Setup との競合に注意） |
| **Semgrep** | `.github/workflows/semgrep.yml` | 事前設定不要（OSS ルールセットで即座に動作） |
| **SonarCloud** | `.github/workflows/sonarcloud.yml`<br>`sonar-project.properties` | 1. [SonarCloud](https://sonarcloud.io/) でプロジェクトを作成<br>2. `SONAR_TOKEN` を GitHub Secrets に設定 |
| **Codecov** | `.github/workflows/codecov.yml`<br>`codecov.yml` | 1. [Codecov](https://about.codecov.io/) にリポジトリを登録<br>2. `CODECOV_TOKEN` を GitHub Secrets に設定（Private リポで必須） |
| **Trivy** | `.github/workflows/trivy.yml` | 事前設定不要（コンテナイメージの脆弱性スキャン） |
| **Snyk** | `.github/workflows/snyk.yml` | 1. [Snyk](https://snyk.io/) でアカウントを作成<br>2. `SNYK_TOKEN` を GitHub Secrets に設定 |

> ⚠️ **CodeQL の注意点**: GitHub リポジトリ設定で「CodeQL Default Setup」が有効になっている場合、`codeql.yml` を追加するとスキャンが重複します。Default Setup をオフにするか、カスタムワークフローの作成をスキップしてください。

---

## 2. ディレクトリ構成

```text
skills/github-quality-setup/
├── README.md                   # 本ドキュメント（人間・管理者向けガイド）
├── SKILL.md                    # AI エージェント用プロンプト・生成ルール
├── references/
│   └── tool-configs.md         # 各ツールの最新ワークフロー/設定テンプレート集
└── evals/
    └── evals.json              # 品質ツール群の生成・推論テストケース
```

---

## 3. 生成される成果物ツリー例

全ツールを有効にした場合、以下のファイル群がリポジトリ内に生成されます。

```text
.github/
  dependabot.yml                # 依存関係の定期更新
  workflows/
    codeql.yml                  # セマンティック脆弱性スキャン
    semgrep.yml                 # 軽量静的解析
    sonarcloud.yml              # コード品質・メンテナビリティ計測
    codecov.yml                 # テストカバレッジ集計
    trivy.yml                   # Docker イメージ脆弱性スキャン
    snyk.yml                    # サードパーティ脆弱性スキャン
.coderabbit.yaml                # AI コードレビュー設定
sonar-project.properties        # SonarCloud プロジェクト定義
codecov.yml                     # カバレッジ閾値・ターゲット設定
```

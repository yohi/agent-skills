# GitHub Release & Package Publishing (管理者・開発者向けガイド)

`googleapis/release-please-action` を使用して、Conventional Commits に基づくリリース PR の自動作成、GitHub Releases の公開、および GitHub Packages（npm, Docker/ghcr.io, Python, Go, Rust 等）への自動パブリッシュを行うスキルの仕様です。
エージェント向け指示は [SKILL.md](SKILL.md) を参照してください。

---

## 1. 事前準備：GitHub リポジトリ設定

ワークフローを正常に動作させるために、人間（リポジトリ管理者）が事前に以下の設定を行います。

### (1) Workflow Permissions の有効化
1. 対象の GitHub リポジトリで **Settings > Actions > General** を開く。
2. **Workflow permissions** セクションで以下を設定:
   - **Read and write permissions** を選択（リリース作成やタグ付けに必要）
   - **Allow GitHub Actions to create and approve pull requests** にチェックを入れる（release-please が自動で PR を作成・マージするために必須）

### (2) パッケージ公開先の前提条件
- **npm (GitHub Packages)**: `package.json` の `name` が `@owner/pkg-name` のように GitHub オーナー名のスコープ付きになっていること。
- **Docker (ghcr.io)**: リポジトリルートに `Dockerfile` が存在すること。
- **crates.io (Rust)**: GitHub Secrets に `CARGO_REGISTRY_TOKEN` が設定されていること。

---

## 2. スクリプトの単体・手動実行

本スキルには、ワークフローファイルを直接生成するヘルパースクリプトが同梱されています。

```bash
# 基本構文
bash skills/github-release-packages/scripts/generate-workflow.sh [language] [package-type]

# 例: Node.js + npm パッケージ公開ワークフローを生成
bash skills/github-release-packages/scripts/generate-workflow.sh node npm

# 例: Docker (ghcr.io) パブリッシュワークフローを生成
bash skills/github-release-packages/scripts/generate-workflow.sh generic docker

# 例: Node.js + Docker 両方のパブリッシュワークフローを生成
bash skills/github-release-packages/scripts/generate-workflow.sh node both
```

**引数オプション:**
- `language`: `node` | `python` | `go` | `rust` | `generic`
- `package-type`: `npm` | `docker` | `both`

生成先: `.github/workflows/release.yml`

---

## 3. ディレクトリ構成

```text
skills/github-release-packages/
├── README.md                 # 本ドキュメント（人間・管理者向けガイド）
├── SKILL.md                  # AI エージェント用プロンプト・自律生成ルール
├── scripts/
│   ├── generate-workflow.sh  # ワークフロー生成 Bash スクリプト
│   └── grade.sh              # 採点・テスト用スクリプト
├── references/               # エージェント用言語別・設定リファレンス
│   ├── manifest-mode.md      # 複数パッケージ/マルチ言語の同期設定
│   ├── nodejs.md             # Node.js / npm 詳細設定
│   ├── python.md             # Python / PyPI 詳細設定
│   ├── docker.md             # Docker (ghcr.io) 詳細設定
│   ├── go.md                 # Go モジュール設定
│   └── rust.md               # Rust / Cargo 設定
└── evals/                    # スキル評価用テストケース
    └── evals.json            # 自律検出・ワークフロー生成のテスト定義
```

---

## 4. リリース運用の流れ

1. 開発者が Conventional Commits（例: `feat: ...`, `fix: ...`）に従ってメインブランチに変更をマージ。
2. `release-please` が自動でバージョン番号と CHANGELOG を計算し、リリース PR を作成・更新。
3. リリース PR をマージすると、自動で GitHub Release と Git タグが作成され、パッケージがビルド・公開されます。

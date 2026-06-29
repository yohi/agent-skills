# Agent Skills

このディレクトリでは、あなた専用の自作エージェントスキル（Agent Skills）を管理します。

## スキルの追加方法

1. `skills/` ディレクトリ内に、新しいスキル名のフォルダを作成します（例：`skills/my-useful-skill/`）。
2. そのフォルダ内に `SKILL.md` を作成し、YAMLフロントマター（`name` と `description`）およびエージェントへの指示を記述します。
3. 必要に応じて、`scripts/` フォルダを追加して実行可能なスクリプトを配置します。

## スキルの構成例

```text
skills/
└── my-useful-skill/
    ├── SKILL.md            # スキルの指示定義（必須）
    └── scripts/            # 実行スクリプト（任意）
        └── run.sh
```

## 移行済みスキル一覧

| スキル名 | 役割 | 使う場面 | 補足 |
|---|---|---|---|
| `doc-sync-verifier` | ドキュメント整合性の検証 | 仕様書・設計書・表の不一致を裏取りしたいとき | ソースコードではなく文書だけを根拠に判断 |
| `git-master` | Git 操作の安全な実行 | コミット分割、履歴整理、履歴調査をしたいとき | Conventional Commits（日本語）に対応 |
| `github-quality-setup` | GitHub 品質・セキュリティ基盤の構築 | CodeRabbit / Dependabot / CodeQL / Semgrep / SonarCloud / Codecov などを入れたいとき | 参照資料として `references/tool-configs.md` と `evals/evals.json` を含む |
| `makefile-organization` | Makefile の分割・整理 | 大きな Makefile を機能別に整理したいとき | 詳細仕様は `REFERENCE.md` に分離 |

必要なら、各スキル名から `skills/<name>/SKILL.md` を開いて詳細を確認してください。

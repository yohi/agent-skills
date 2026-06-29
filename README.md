# Agent Skills (Self-Managed)

AIコーディングエージェントに適用するための、自作のカスタムスキル（Agent Skills）を管理・開発するリポジトリです。

---

## プロジェクト構成

本リポジトリは以下のシンプルな構成で自作スキルを管理します。

```text
agent-skills/
├── skills/
│   ├── README.md               # 自作スキルの追加・運用ガイド
│   ├── doc-sync-verifier/
│   ├── git-master/
│   ├── github-quality-setup/
│   └── makefile-organization/
└── AGENTS.md                   # エージェント向けの動作指示・ルール定義
```

---

## 🚀 クイックスタート

### 1. Claude Code での使用
本リポジトリを Claude Code のプラグインとしてローカルで読み込ませて使用します。

```bash
git clone https://github.com/yohi/agent-skills.git
claude --plugin-dir /path/to/agent-skills
```

### 2. Cursor での使用
`.cursor/rules/` に必要なスキル（`SKILL.md`）を直接コピーするか、Cursor の設定から `skills/` ディレクトリを直接参照させて使用します。

### 3. Antigravity CLI での使用
プラグインとしてインストールします。

```bash
agy plugin install https://github.com/yohi/agent-skills.git
# またはローカルクローンから
agy plugin install ./agent-skills
```

---

## 🛠️ 新しいスキルの作成手順

1. `skills/` 配下に新しいスキル名のフォルダを `kebab-case` で作成します（例: `skills/my-new-workflow/`）。
2. フォルダ内に `SKILL.md` を作成し、YAMLフロントマター（`name` と `description`）を記述します。
3. エージェントが実行すべき手順、危険信号（Red Flags）、および検証（Verification）を記述します。
4. （任意）実行に必要なスクリプトを `scripts/` ディレクトリ配下に配置します。

> [!IMPORTANT]
> スキルを作成・変更した際は、コミット前に必ずローカルの検証スクリプトを実行し、エラーがないことを確認してください。
> ```bash
> node scripts/validate-skills.js
> ```

# Makefile Organization (開発者向けガイド)

肥大化した Makefile（数百〜1000行以上）を、保守性・再利用性の高いモジュール構成（`_mk/` ディレクトリ配下）に分割・整理するためのスキルです。
エージェント向け指示は [SKILL.md](SKILL.md) を、詳細なマクロ仕様やチェックリストは [REFERENCE.md](REFERENCE.md) を参照してください。

---

## 1. モジュール分割アーキテクチャ

メインの `Makefile` は include ディレクティブと最小限のエントリポイントのみを保持し、機能ごとに `_mk/` に分割します。

```text
Makefile                      # メインエントリポイント (include _mk/*.mk)
└── _mk/
    ├── variables.mk          # 共通変数・PHONY一覧
    ├── idempotency.mk        # 冪等性（スキップ）マクロ定義
    ├── help.mk               # ヘルプ表示
    ├── system.mk / install.mk# 各種セットアップ・インストール処理
    └── test.mk               # テスト実行ターゲット
```

### レイヤー順の include 規則
1. **Core**: `variables.mk`, `idempotency.mk`, `help.mk`
2. **Infrastructure**: `bitwarden.mk` 等
3. **Functional**: `system.mk`, `install.mk`, `setup.mk` 等
4. **Meta**: `main.mk`, `stages.mk` 等
5. **AI & Tools**: `claude.mk`, `gemini.mk`, `opencode.mk` 等
6. **Testing**: `test.mk`

---

## 2. ディレクトリ構成

```text
skills/makefile-organization/
├── README.md                 # 本ドキュメント（開発者向けガイド）
├── SKILL.md                  # AI エージェント用プロンプト・命名/構造化規約
└── REFERENCE.md              # エージェント用詳細仕様（マクロ、エラー処理、チェックリスト）
```

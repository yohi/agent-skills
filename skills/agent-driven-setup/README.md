# Agent-driven Setup

任意の GitHub またはローカルリポジトリを解析し、そのリポジトリに適した **AI エージェント主導の自律セットアップフレームワーク** を導入するスキルです。

## 主な用途

- リポジトリに「AI coding agent へ短いプロンプトを渡すだけで setup が進む」仕組みを追加したい
- 既存の README インストール手順を Agent-friendly に再設計したい
- 既存の installer / Makefile / CI を尊重しつつ、Human → Agent の setup handoff を構築したい
- 秘密情報を安全に扱いながら、contributor や end user の setup を自動化したい

## このスキルが行うこと

1. 対象リポジトリの既存 setup assets（README、install docs、package metadata、CI、Agent config など）を調査
2. リポジトリ固有の setup contract を理解し、最適な Agent-driven setup アプローチを選択
3. Human-facing な README エントリポイントを追加
4. 必要に応じて Agent setup protocol（主に `AGENTS.md` 内）を追加・追記
5. 実際の setup path を可能な範囲で検証
6. 変更内容、再利用した既存 assets、検証結果、未検証事項を報告

## このスキルが行わないこと

- 固定テンプレートを全リポジトリに無条件適用
- 既存の手動 setup 手順や CI を削除
- 勝手に commit / push / PR 作成
- 外部クラウドリソースや有料リソースの自動作成
- secret value を chat や生成ファイル、レポートに含める

## エージェント向け指示

詳細な手順と制約は [`SKILL.md`](SKILL.md) を参照してください。

Language: [English](README.md) | 日本語

# skill-stocktake

Claude のスキルの品質を監査する [Agent Skill](https://agentskills.io/specification) です。インストール済みの全スキルを 1 つのコンテキストで読み込み、AI の総合判断により Keep / Improve / Update / Retire / Merge の判定を出します。

## インストール

### Claude Code

```bash
# スキルをグローバルスキルディレクトリにコピー
cp -r skills/skill-stocktake ~/.claude/skills/skill-stocktake
```

### SkillsMP

```bash
/skills add shimo4228/skill-stocktake
```

## モード

| モード | トリガー | 動作 |
|--------|----------|------|
| **full** | デフォルト、または `/skill-stocktake full` | 全スキルを読み込んで評価 |
| **changed** | `/skill-stocktake changed` | 前回以降に `SKILL.md` が変更されたスキルのみ再評価。残りは台帳から引き継ぐ |

## 仕組み

スキャンスクリプトもサブエージェントのバッチ分割もありません。大きなコンテキストウィンドウを前提に、Glob でスキルを列挙し、全スキルを 1 つのコンテキストに読み込みます。この「一括して見る」視点こそが、スキル間の重複検出を正確にします。

1. **Phase 1 — インベントリ**: `~/.claude/skills/*/SKILL.md` + `learned/*.md`（および `$PWD/.claude/skills/` があればプロジェクトスキル）を Glob で列挙。Glob はスキル定義ファイルのみを対象とするため、`.venv` / `.pytest_cache` 配下の依存 markdown は構造的に除外され、prune は不要です。使用回数は、使用ログ hook が導入されていれば `~/.claude/metrics/skill-usage.jsonl` をインラインで読み取ります。
2. **Phase 2 — 評価**: 全スキル本文を読み、チェックリストを一括適用します — 内容重複（ドキュメント化された orchestrator/sub-skill の層分けは重複ではない）、MEMORY/CLAUDE.md/rules との重複、参照の鮮度、使用頻度。
3. **Phase 3 — サマリー**: 自己完結した理由付きの判定テーブル。
4. **Phase 4 — 統合**: Retire/Merge はユーザー確認後にのみ実行。Improve/Update は改善エンジンである Anthropic 純正の [`skill-creator`](https://github.com/anthropics/skills) へのハンドオフとして提示します。判定台帳（`results.json`）はインラインで更新します。

## 判定基準

| 判定 | 意味 |
|------|------|
| **Keep** | 有用かつ最新の状態 |
| **Improve** | 維持する価値はあるが、具体的な改善が必要 |
| **Update** | 参照している技術が古くなっている |
| **Retire** | 品質が低い、陳腐化している、またはコスト対効果が悪い |
| **Merge into [X]** | 他のスキルと大幅に重複している |

## 要件

- **Glob**・**Read**・**Bash** ツールをサポートする Claude Code（監査は 1 つのメインコンテキストで実行 — サブエージェント不要）。
- 任意: 小さなインラインワンライナー（changed モードのタイムスタンプ確認、使用回数集計）用に `jq` と `python3`。無くても機能は劣化せず動作します。

## このスキルについて

このスキルは [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) の **Curate** フェーズを実装する — エージェント行動とオペレーターの判断が共発展する 6 フェーズ双方向成長ループ ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726))。AKC は [@shimo4228](https://github.com/shimo4228) の 3 つの研究ラインの 1 つで、他に [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — 4 つの contemplative 公理に基づく自律エージェント — と [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — 自律 AI エージェントの責任分配に関するハーネス中立 ADR — がある。

## ライセンス

MIT

Language: [English](README.md) | 日本語

# claude-skill-stocktake

Claude のスキルとコマンドの品質を監査する [Agent Skill](https://agentskills.io/specification) です。チェックリスト + AI の総合判断により、Keep / Improve / Update / Retire / Merge の判定を出します。

## インストール

### Claude Code

```bash
# スキルとスクリプトをグローバルスキルディレクトリにコピー
cp -r skills/skill-stocktake ~/.claude/skills/skill-stocktake
```

### SkillsMP

```bash
/skills add shimo4228/claude-skill-stocktake
```

## モード

| モード | トリガー | 所要時間 |
|--------|----------|----------|
| **Quick Scan** | `results.json` が存在する場合（デフォルト） | 5〜10 分 |
| **Full Stocktake** | `results.json` が存在しない場合、または `/skill-stocktake full` | 20〜30 分 |

## 仕組み

### Quick Scan
前回の実行以降に変更されたスキルのみを再評価します。`scripts/quick-diff.sh` で mtime の変化を検出し、変更のなかったスキルの結果はそのまま引き継ぎます。

### Full Stocktake

1. **Phase 1 — インベントリ**: `scripts/scan.sh` が全スキルファイルを列挙し、フロントマターの抽出と使用統計の収集を行います
2. **Phase 2 — 品質評価**: AI サブエージェントが各スキルを読み込み、チェックリスト（重複・鮮度・使用頻度）を適用します
3. **Phase 3 — サマリーテーブル**: アクション理由付きの判定結果を出力します
4. **Phase 4 — 統合**: Retire / Merge / Improve のアクションをユーザー確認のうえ実行します

## 判定基準

| 判定 | 意味 |
|------|------|
| **Keep** | 有用かつ最新の状態 |
| **Improve** | 維持する価値はあるが、具体的な改善が必要 |
| **Update** | 参照している技術が古くなっている |
| **Retire** | 品質が低い、陳腐化している、またはコスト対効果が悪い |
| **Merge into [X]** | 他のスキルと大幅に重複している |

## スクリプト

| スクリプト | 用途 |
|------------|------|
| `scripts/scan.sh` | フロントマターと mtime を含むスキルファイルの列挙 |
| `scripts/quick-diff.sh` | 前回の評価以降に変更・追加されたスキルの検出 |
| `scripts/save-results.sh` | 評価結果を `results.json` にマージ |

## 要件

- `jq`（JSON 処理）
- `bash` 4 以上
- Agent ツールをサポートする Claude Code（AI 評価に使用）

## このスキルについて

このスキルは [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) の **Curate** フェーズを実装する — エージェント行動とオペレーターの判断が共発展する 6 フェーズ双方向成長ループ ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726))。AKC は [@shimo4228](https://github.com/shimo4228) の 3 つの研究ラインの 1 つで、他に [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — 4 つの contemplative 公理に基づく自律エージェント — と [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — 自律 AI エージェントの責任分配に関するハーネス中立 ADR — がある。

## ライセンス

MIT

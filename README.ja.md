Language: [English](README.md) | 日本語

# skill-stocktake

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shimo4228/skill-stocktake) [![GitMCP](https://img.shields.io/endpoint?url=https://gitmcp.io/badge/shimo4228/skill-stocktake)](https://gitmcp.io/shimo4228/skill-stocktake)

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

## 使用計測 Hook（任意）

監査の使用回数列（7/30/90 日カウント）は `~/.claude/metrics/skill-usage.jsonl` を読みます。このログを書く hook — `hooks/log-skill-usage.sh` — と bats テスト一式を本 repo に同梱しています。無くても監査は動作します（使用回数が `—`（未計測）になるだけ）。

記録するイベントは 3 種類: `invoke`（Skill tool 呼び出し）、`read`（スキル `.md` の Read）、`slash`（ユーザーが `/skill` とタイプした起動。プロンプト送信時に捕捉 — この経路は Skill tool も Read も経由しないため、このイベント無しでは user-invocable スキルが系統的に過小計上されます）。

> **Claude Code 専用。** スクリプトは Claude Code の hook ペイロード（stdin の PostToolUse / UserPromptSubmit JSON）を解析します。実体は素の bash + `jq` 約 90 行なので、他ハーネス（Codex CLI, Gemini CLI 等）のユーザーはフィールド名と配線を各自のフック機構に合わせて微修正すれば流用できます。

### インストール（Claude Code）

```bash
cp hooks/log-skill-usage.sh ~/.claude/hooks/
```

`~/.claude/settings.json` の 2 つのイベントに配線します:

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Read|Skill",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/log-skill-usage.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/log-skill-usage.sh" }] }
    ]
  }
}
```

`bats tests/log-skill-usage.bats`（14 テスト）で検証できます。

## モード

| モード | トリガー | 動作 |
|--------|----------|------|
| **full** | デフォルト、または `/skill-stocktake full` | 全スキルを読み込んで評価 |
| **changed** | `/skill-stocktake changed` | 前回以降に `SKILL.md` が変更されたスキルのみ再評価。残りは台帳から引き継ぐ |

## 仕組み

スキャンスクリプトもサブエージェントのバッチ分割もありません。大きなコンテキストウィンドウを前提に、Glob でスキルを列挙し、全スキルを 1 つのコンテキストに読み込みます。この「一括して見る」視点こそが、スキル間の重複検出を正確にします。

1. **Phase 1 — インベントリ**: `~/.claude/skills/*/SKILL.md` + `learned/*.md`（および `$PWD/.claude/skills/` があればプロジェクトスキル）を Glob で列挙。Glob はスキル定義ファイルのみを対象とするため、`.venv` / `.pytest_cache` 配下の依存 markdown は構造的に除外され、prune は不要です。使用回数は、同梱の使用計測 hook（「使用計測 Hook」節参照）が導入されていれば `~/.claude/metrics/skill-usage.jsonl` をインラインで読み取ります。
2. **Phase 2 — 評価**: 全スキル本文を読み、2 段の binary スクリーンを適用します — Stage 1 はスキルごとの Yes/No チェックリスト（内容重複〔ドキュメント化された orchestrator/sub-skill の層分けは重複ではない〕、MEMORY/CLAUDE.md/rules との重複、参照の鮮度、使用頻度）、Stage 2 は非 Keep の暫定判定に対しスキル固有の反証質問を生成して確定前に圧力テストします。binary 回答は総合判定の証拠であり、スコアに集約しません。
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

## 参考研究

監査の **集合コスト (aggregate cost)** 次元 — 大きく未整理なスキルライブラリはエージェントのスキル選択を劣化させ、挙動を no-skill ベースラインへ引き戻すため、ライブラリが大きいほど Keep のバーが上がる — は、2026 年のエージェントスキルライブラリに関する経験的研究に基づく:

- [How Well Do Agentic Skills Work in the Wild](https://arxiv.org/abs/2604.04323) (Liu et al., 2026) — 現実的な設定では、大きく未整理なライブラリから検索するほどスキルの利得が弱まる。
- [SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks](https://arxiv.org/abs/2602.12670) (Li et al., 2026) — キュレーションはドメイン横断で大きく不均一な利得を生む。スキルの品質は結果に非線形に効く。
- [SkillOps: Managing LLM Agent Skill Libraries as Self-Maintaining Software Ecosystems](https://arxiv.org/abs/2605.13716) (Pu, Song & Zhao, 2026) — 「スキル技術的負債」とライブラリ健全性の維持を第一級の規律として定式化。

skill-stocktake は **何を残すかの判断** を人間に保持する（監査は判定を提案し、確定はユーザーが行う）— 上記の自己維持システムとの差分はここにある。

## このスキルについて

このスキルは [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) の **Curate** フェーズを実装する — エージェント行動とオペレーターの判断が共発展する 6 フェーズ双方向成長ループ ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726))。AKC は [@shimo4228](https://github.com/shimo4228) の 3 つの研究ラインの 1 つで、他に [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — 4 つの contemplative 公理に基づく自律エージェント — と [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — 自律 AI エージェントの責任分配に関するハーネス中立 ADR — がある。

## ライセンス

MIT

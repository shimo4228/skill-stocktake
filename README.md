Language: English | [日本語](README.ja.md)

# skill-stocktake

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shimo4228/skill-stocktake) [![GitMCP](https://img.shields.io/endpoint?url=https://gitmcp.io/badge/shimo4228/skill-stocktake)](https://gitmcp.io/shimo4228/skill-stocktake) [![View Code Wiki](https://assets.codewiki.google/readme-badge/static.svg)](https://codewiki.google/github.com/shimo4228/skill-stocktake)

An [Agent Skill](https://agentskills.io/specification) that audits all your Claude skills for quality. It reads every installed skill in one context and applies AI holistic judgment to produce Keep / Improve / Update / Retire / Merge verdicts.

## Install

### Claude Code

```bash
# Copy the skill into your global skills directory
cp -r skills/skill-stocktake ~/.claude/skills/skill-stocktake
```

### SkillsMP

```bash
/skills add shimo4228/skill-stocktake
```

## Modes

| Mode | Trigger | What it does |
|------|---------|--------------|
| **full** | default, or `/skill-stocktake full` | Read and evaluate every skill |
| **changed** | `/skill-stocktake changed` | Re-evaluate only skills whose `SKILL.md` changed since the last run; carry the rest forward from the ledger |

## How It Works

No scan scripts and no subagent batching — with a large context window the skill enumerates skills with Glob and reads them all into one context. That single-context view is what makes cross-skill overlap detection accurate.

1. **Phase 1 — Inventory**: Glob `~/.claude/skills/*/SKILL.md` + `learned/*.md` (and project skills under `$PWD/.claude/skills/` if present). Because Glob targets only skill definition files, dependency markdown under `.venv` / `.pytest_cache` is excluded structurally — no pruning needed. Usage counts are read inline from `~/.claude/metrics/skill-usage.jsonl` if a usage hook is installed.
2. **Phase 2 — Evaluation**: read every skill body and apply the checklist holistically — content overlap (a documented orchestrator/sub-skill split is *not* overlap), MEMORY/CLAUDE.md/rules overlap, reference freshness, usage frequency.
3. **Phase 3 — Summary**: a per-skill verdict table with self-contained reasons.
4. **Phase 4 — Consolidation**: Retire/Merge act only after you confirm; Improve/Update are offered as a hand-off to Anthropic's official [`skill-creator`](https://github.com/anthropics/skills) skill, the improvement engine. The verdict ledger (`results.json`) is updated inline.

## Verdict Criteria

| Verdict | Meaning |
|---------|---------|
| **Keep** | Useful and current |
| **Improve** | Worth keeping, but specific improvements needed |
| **Update** | Referenced technology is outdated |
| **Retire** | Low quality, stale, or cost-asymmetric |
| **Merge into [X]** | Substantial overlap with another skill |

## Requirements

- Claude Code with the **Glob**, **Read**, and **Bash** tools (the audit runs in one main context — no subagents required).
- Optional: `jq` and `python3` for the small inline one-liners (changed-mode timestamp check, usage aggregation). The skill degrades gracefully without them.

## About this skill

This skill implements the **Curate** phase of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) — a Zenodo-citable six-phase bidirectional growth loop ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726)) for sustaining intent alignment between an AI agent and its operator over time. AKC is one of three research lines by [@shimo4228](https://github.com/shimo4228), alongside [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — autonomous agents grounded in four contemplative axioms — and [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — harness-neutral ADRs on accountability distribution.

## License

MIT

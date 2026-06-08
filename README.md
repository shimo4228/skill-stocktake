Language: English | [日本語](README.ja.md)

# skill-stocktake

An [Agent Skill](https://agentskills.io/specification) that audits all your Claude skills and commands for quality. Uses a checklist + AI holistic judgment to produce Keep / Improve / Update / Retire / Merge verdicts.

## Install

### Claude Code

```bash
# Copy skill + scripts into your global skills directory
cp -r skills/skill-stocktake ~/.claude/skills/skill-stocktake
```

### SkillsMP

```bash
/skills add shimo4228/skill-stocktake
```

## Modes

| Mode | Trigger | Duration |
|------|---------|----------|
| **Quick Scan** | `results.json` exists (default) | 5-10 min |
| **Full Stocktake** | `results.json` absent, or `/skill-stocktake full` | 20-30 min |

## How It Works

### Quick Scan
Re-evaluates only skills that changed since the last run. Uses `scripts/quick-diff.sh` to detect mtime changes, then carries forward unchanged results.

### Full Stocktake

1. **Phase 1 — Inventory**: `scripts/scan.sh` enumerates all skill files, extracts frontmatter, and collects usage stats
2. **Phase 2 — Quality Evaluation**: AI subagent reads each skill and applies the checklist (overlap, freshness, usage frequency)
3. **Phase 3 — Summary Table**: Verdicts with actionable reasons
4. **Phase 4 — Consolidation**: Retire/Merge/Improve actions with user confirmation

## Verdict Criteria

| Verdict | Meaning |
|---------|---------|
| **Keep** | Useful and current |
| **Improve** | Worth keeping, but specific improvements needed |
| **Update** | Referenced technology is outdated |
| **Retire** | Low quality, stale, or cost-asymmetric |
| **Merge into [X]** | Substantial overlap with another skill |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/scan.sh` | Enumerate skill files with frontmatter and mtime |
| `scripts/quick-diff.sh` | Detect changed/new skills since last evaluation |
| `scripts/save-results.sh` | Merge evaluation results into `results.json` |

## Requirements

- `jq` (JSON processing)
- `bash` 4+
- Claude Code with Agent tool support (for AI evaluation)

## About this skill

This skill implements the **Curate** phase of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) — a Zenodo-citable six-phase bidirectional growth loop ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726)) for sustaining intent alignment between an AI agent and its operator over time. AKC is one of three research lines by [@shimo4228](https://github.com/shimo4228), alongside [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — autonomous agents grounded in four contemplative axioms — and [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — harness-neutral ADRs on accountability distribution.

## License

MIT

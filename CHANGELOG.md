# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- Subagent reference updated: `Task tool / Explore agent` → `Agent tool / general-purpose` to match the current Claude Code harness tool naming
- Restored full SKILL.md frontmatter (`name`, `license`, `metadata.{author,version,extracted}`, `origin`) from canonical
- Normalized en-dash to ASCII hyphen across phase duration and section ranges
- Requirements line in `README.md`, `README.ja.md`, and `llms-full.txt` updated to "Agent tool support"

### What it does

A Claude Code Agent Skill that audits all installed skills and commands for quality. Uses a checklist plus AI holistic judgment to produce Keep / Improve / Update / Retire / Merge verdicts. Supports two modes: **Quick Scan** (5-10 min) re-evaluates only skills that have changed since the last run; **Full Stocktake** (20-30 min) re-evaluates everything in a sequential subagent batch.

### Components

- `skills/skill-stocktake/SKILL.md` — the skill body. Two-mode runbook (Quick Scan + Full Stocktake), the quality checklist, and the verdict taxonomy.
- `scripts/quick-diff.sh` — shell script that compares current skill mtimes against the cached `results.json` to identify changed skills for Quick Scan mode.

### Scope

The skill assumes Claude Code's `~/.claude/skills/` (global) and `$PWD/.claude/skills/` (project) as the audit surface. Verdicts are advisory; the operator decides whether to act on each. Designed to keep the skills surface from accumulating low-signal entries that pollute future sessions and degrade trigger accuracy.

### Requirements

- `jq` (JSON processing for the results cache)
- `bash` 4 or later
- Claude Code with Agent tool support (for the AI evaluation phase)

### Relationship to companion skills

| Skill | Role | When |
|---|---|---|
| [`search-first`](https://github.com/shimo4228/search-first) | Research before coding | Earlier phase of the AKC knowledge lifecycle |
| [`learn-eval`](https://github.com/shimo4228/learn-eval) | Per-session pattern extraction with quality gate | Later phase — feeds new patterns after stocktake clears retired entries |
| [`rules-distill`](https://github.com/shimo4228/rules-distill) | Promote cross-cutting principles to rules | Final phase of the lifecycle |

This skill implements the **Curate** phase of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) — a Zenodo-citable six-phase bidirectional growth loop for sustaining intent alignment between an AI agent and its operator over time.

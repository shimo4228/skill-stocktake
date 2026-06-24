# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-06-24

Major redesign for the large-context era. The skill dropped its shell-script
scanning layer and subagent batching in favor of inline Glob enumeration and a
single-context holistic evaluation.

### Changed

- **Removed all scan scripts** (`scripts/scan.sh`, `quick-diff.sh`, `save-results.sh`). Inventory is now a Glob over `~/.claude/skills/*/SKILL.md` + `learned/*.md`; the merge/diff steps are inline Read/Write and a one-line `find -newermt` check.
- **Removed subagent batching.** Every skill is read into one context and evaluated together. Batching blinded each subagent to skills in other batches and missed cross-skill overlap; a single-context view is what makes overlap detection accurate.
- **Modes renamed**: Quick Scan / Full Stocktake → `full` (default) and `changed`.
- **`results.json` is now a lean verdict ledger** — `{evaluated_at, skills:{name:{path,verdict,reason,mtime}}}`. Dropped `mode` / `batch_progress` / resume state.
- **Improve/Update verdicts hand off to [`skill-creator`](https://github.com/shimo4228/skill-creator)** (the improvement engine); stocktake itself stays audit-only.
- **SKILL.md body rewritten in English** for publication.

### Fixed

- The old `find -name "*.md"` counted dependency markdown under `.venv` / `.pytest_cache` as "skills", inflating inventory counts and polluting change diffs. Glob over skill-definition files excludes that noise structurally.

### Requirements

- Claude Code with the Glob / Read / Bash tools (no subagents required).
- Optional: `jq` and `python3` for the inline timestamp / usage one-liners.

### Validated

- Benchmarked against a no-skill baseline with the `skill-creator` eval harness (2 evals, with_skill vs without_skill). The skill's measurable advantage is inventory completeness: it audited all 65 skills including the `learned/` notes and excluded `.venv` noise, where the baseline covered only 47 and tripped over `.venv`.

## [1.0.0]

Initial release: checklist-plus-AI audit with Quick Scan / Full Stocktake modes,
backed by `scripts/{scan,quick-diff,save-results}.sh` and a `results.json` cache.

---

## About

A Claude Code Agent Skill that audits all installed skills for quality and produces
Keep / Improve / Update / Retire / Merge verdicts. It implements the **Curate** phase
of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) —
a Zenodo-citable six-phase bidirectional growth loop for sustaining intent alignment
between an AI agent and its operator over time.

### Relationship to companion skills

| Skill | Role | When |
|---|---|---|
| [`search-first`](https://github.com/shimo4228/search-first) | Research before coding | Earlier phase of the AKC knowledge lifecycle |
| [`skill-creator`](https://github.com/shimo4228/skill-creator) | Author / improve a single skill | Where stocktake hands off Improve/Update work |
| [`learn-eval`](https://github.com/shimo4228/learn-eval) | Per-session pattern extraction with quality gate | Later phase — feeds new patterns after stocktake clears retired entries |
| [`rules-distill`](https://github.com/shimo4228/rules-distill) | Promote cross-cutting principles to rules | Final phase of the lifecycle |

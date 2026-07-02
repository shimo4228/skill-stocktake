# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Two-stage binary evaluation.** Phase 2 now runs a Stage 1 binary screen (per-skill Yes/No checklist; only No answers are surfaced) and, for non-Keep draft verdicts only, a Stage 2 pressure-test of 1-3 skill-specific refutation questions answered with one line of evidence each. A refuted defect falls back to Keep; a confirmed defect becomes the improvement list handed to skill-creator. Binary answers stay evidence for a holistic verdict — never aggregated into a score (BinEval arXiv:2606.27226; CheckEval; TICK).
- **`slash` usage events.** The usage log now distinguishes `invoke` (Skill tool), `read` (skill-file Reads), and `slash` (user-typed `/skill` invocations captured at prompt submission). The slash path previously fired neither the Skill tool nor a Read — command-message injection made user-invocable skills systematically undercounted. Aggregation instructions state the 2026-07-03 boundary: earlier windows are lower bounds for user-invocable skills, and low usage alone must not Retire a slash-driven skill.
- **Bundled measurement hook.** `hooks/log-skill-usage.sh` (Claude Code–specific: parses PostToolUse / UserPromptSubmit stdin JSON; plain bash + jq, adaptable to other harnesses) and its 14-test bats suite (`tests/log-skill-usage.bats`) now ship with the repo, with install/wiring instructions in the README.

- **Aggregate-cost evaluation dimension.** The audit now weighs set-level library cost, not only per-skill quality: a large, uncurated library degrades skill selection and pulls behaviour toward the no-skill baseline, so the Keep bar rises with library size and a merely-adequate skill becomes a Retire/Merge candidate on aggregate-dilution grounds alone. A judgment input, never a quota. Grounded in 2026 skill-library benchmarks (Liu et al. arXiv:2604.04323; Li et al. arXiv:2602.12670; SkillOps arXiv:2605.13716) — see README "References".

## [2.0.0] - 2026-06-24

Major redesign for the large-context era. The skill dropped its shell-script
scanning layer and subagent batching in favor of inline Glob enumeration and a
single-context holistic evaluation.

### Changed

- **Removed all scan scripts** (`scripts/scan.sh`, `quick-diff.sh`, `save-results.sh`). Inventory is now a Glob over `~/.claude/skills/*/SKILL.md` + `learned/*.md`; the merge/diff steps are inline Read/Write and a one-line `find -newermt` check.
- **Removed subagent batching.** Every skill is read into one context and evaluated together. Batching blinded each subagent to skills in other batches and missed cross-skill overlap; a single-context view is what makes overlap detection accurate.
- **Modes renamed**: Quick Scan / Full Stocktake → `full` (default) and `changed`.
- **`results.json` is now a lean verdict ledger** — `{evaluated_at, skills:{name:{path,verdict,reason,mtime}}}`. Dropped `mode` / `batch_progress` / resume state.
- **Improve/Update verdicts hand off to Anthropic's official [`skill-creator`](https://github.com/anthropics/skills)** (the improvement engine, not a shimo4228 skill); stocktake itself stays audit-only.
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
| [`skill-creator`](https://github.com/anthropics/skills) (Anthropic, not shimo4228) | Author / improve a single skill | Where stocktake hands off Improve/Update work |
| [`learn-eval`](https://github.com/shimo4228/learn-eval) | Per-session pattern extraction with quality gate | Later phase — feeds new patterns after stocktake clears retired entries |
| [`rules-distill`](https://github.com/shimo4228/rules-distill) | Promote cross-cutting principles to rules | Final phase of the lifecycle |

Language: English | [日本語](README.ja.md)

# skill-stocktake

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shimo4228/skill-stocktake) [![GitMCP](https://img.shields.io/endpoint?url=https://gitmcp.io/badge/shimo4228/skill-stocktake)](https://gitmcp.io/shimo4228/skill-stocktake)

An [Agent Skill](https://agentskills.io/specification) that audits all your Claude skills for quality. It combines a deterministic structural pre-pass, per-skill scrutiny in small fresh-context batches, and a dedicated cross-skill overlap probe to produce Keep / Improve / Update / Retire / Merge verdicts — by holistic judgment, never a numeric score.

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

## Usage Measurement Hook (optional)

The audit's usage column (7/30/90-day counts) reads `~/.claude/metrics/skill-usage.jsonl`. This repo bundles the hook that writes that log — `hooks/log-skill-usage.sh` — plus its bats test suite. Without it the audit still works; usage just renders as `—` (unmeasured).

It logs three event types: `invoke` (Skill-tool calls), `read` (Reads of skill `.md` files), and `slash` (user-typed `/skill` invocations, captured at prompt submission — these bypass both the Skill tool and Read, so without this event user-invocable skills are systematically undercounted).

> **Claude Code–specific.** The script parses Claude Code's hook payloads (PostToolUse / UserPromptSubmit JSON on stdin). It is ~90 lines of plain bash + `jq`, so users of other harnesses (Codex CLI, Gemini CLI, …) can adapt the field names and wiring to their own hook mechanism.

### Install (Claude Code)

```bash
cp hooks/log-skill-usage.sh ~/.claude/hooks/
```

Then wire it in `~/.claude/settings.json` under both events:

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

Verify with `bats tests/log-skill-usage.bats` (14 tests).

## Modes

| Mode | Trigger | What it does |
|------|---------|--------------|
| **full** | default, or `/skill-stocktake full` | Read and evaluate every skill |
| **changed** | `/skill-stocktake changed` | Re-evaluate only skills whose `SKILL.md` changed since the last run; carry the rest forward from the ledger |

## How It Works

The architecture splits the audit by the *property being checked*, not by context length. Deterministic checks are code-owned and unconditional; per-item judgment gets narrow, dense contexts; set-level judgment gets a light description sweep with targeted deep reads. (v2.0 read everything into one context on the large-context-window premise; a controlled comparison on a 73-skill library showed per-item scrutiny dilutes there — the single-context pass returned all-Keep while fresh-context batches surfaced 12 non-Keep verdicts, half with deterministic evidence — while a dedicated overlap probe recovered the set-level view without needing all bodies in one context.)

1. **Phase 0 — Structural pre-pass (deterministic)**: run the [skill-health](https://github.com/shimo4228/skill-health) scanner for dangling references and missing artifacts, and enforce ledger hygiene (canonical keys, existing paths). A skill that fails the existence check never reaches judgment.
2. **Phase 1 — Inventory**: Glob `~/.claude/skills/*/SKILL.md` + `learned/*.md` (and project skills under `$PWD/.claude/skills/` if present). Usage counts are read inline from `~/.claude/metrics/skill-usage.jsonl` if the bundled usage hook is installed (see "Usage Measurement Hook").
3. **Phase 2 — Per-item scrutiny (parallel small batches)**: split into batches of 10–12 and launch one subagent per batch, each with a fresh context. Stage 1 is a per-skill Yes/No screen (actionability; scope fit; within-batch uniqueness; currency — with **unconditional** verification of every named path, flag, and URL: "verify if it looks stale" is banned phrasing, because the condition itself dilutes in a loaded context). Stage 2 generates skill-specific refutation questions that pressure-test any non-Keep draft verdict. Binary answers are evidence for a holistic verdict, never aggregated into a score. Batch agents never see prior verdicts (anchoring) or usage data (parent-owned).
4. **Phase 3 — Overlap probe (dedicated agent)**: one agent sweeps every skill's name + description, proposes candidate clusters greedily, then reads candidate bodies side by side to judge genuine duplication vs documented layering vs adjacent-but-distinct. Only confirmed genuine duplication produces Merge verdicts.
5. **Phase 4 — Synthesis**: the parent merges batch verdicts, overlap verdicts, and usage data (zero-usage rule, aggregate-cost judgment), and renders a per-skill verdict table with self-contained reasons.
6. **Phase 5 — Consolidation**: non-Keep candidates are confirmed **one by one** — evidence first, then `[y/n/skip]`, never bulk approval. Retire/Merge act only after you confirm that file; Improve/Update are offered per skill as a hand-off to Anthropic's official [`skill-creator`](https://github.com/anthropics/skills) skill, the improvement engine. The verdict ledger (`results.json`) is updated inline.

## Verdict Criteria

| Verdict | Meaning |
|---------|---------|
| **Keep** | Useful and current |
| **Improve** | Worth keeping, but specific improvements needed |
| **Update** | Referenced technology is outdated |
| **Retire** | Low quality, stale, or cost-asymmetric |
| **Merge into [X]** | Substantial overlap with another skill |

## Requirements

- Claude Code with the **Glob**, **Read**, **Bash**, and **subagent (Task/Agent)** tools (Phase 2 batches and the Phase 3 overlap probe run as parallel subagents).
- Optional: `jq` and `python3` for the small inline one-liners (changed-mode timestamp check, usage aggregation). The skill degrades gracefully without them.

## References

The **aggregate-cost** dimension of the audit — a large, uncurated skill library degrades the agent's ability to select the right skill and pulls behaviour back toward the no-skill baseline, so the Keep bar rises with library size — is grounded in 2026 empirical work on agent skill libraries:

- [How Well Do Agentic Skills Work in the Wild](https://arxiv.org/abs/2604.04323) (Liu et al., 2026) — skill benefits weaken in realistic settings as the agent must retrieve from a large, uncurated library.
- [SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks](https://arxiv.org/abs/2602.12670) (Li et al., 2026) — curation produces large, uneven gains across domains; skill quality has a non-linear effect on outcome.
- [SkillOps: Managing LLM Agent Skill Libraries as Self-Maintaining Software Ecosystems](https://arxiv.org/abs/2605.13716) (Pu, Song & Zhao, 2026) — frames "skill technical debt" and library-health maintenance as a first-class discipline.

skill-stocktake keeps the *judgment of what stays* with the human — the audit proposes verdicts and you confirm them — which is its delta from the self-maintaining systems above.

## About this skill

This skill implements the **Curate** phase of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) — a Zenodo-citable six-phase bidirectional growth loop ([DOI 10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726)) for sustaining intent alignment between an AI agent and its operator over time. AKC is one of three research lines by [@shimo4228](https://github.com/shimo4228), alongside [Contemplative Agent](https://github.com/shimo4228/contemplative-agent) ([DOI 10.5281/zenodo.19212118](https://doi.org/10.5281/zenodo.19212118)) — autonomous agents grounded in four contemplative axioms — and [Agent Attribution Practice (AAP)](https://github.com/shimo4228/agent-attribution-practice) ([DOI 10.5281/zenodo.19652013](https://doi.org/10.5281/zenodo.19652013)) — harness-neutral ADRs on accountability distribution.

## License

MIT

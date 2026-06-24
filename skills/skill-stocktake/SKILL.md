---
name: skill-stocktake
description: Audit installed Claude skills for quality and surface Keep/Improve/Update/Retire/Merge verdicts. Use when the user says "audit my skills", "stocktake", "review my skills", "which skills should I retire or merge", "do a quality pass over my skills", or "/skill-stocktake". NOT for creating or improving a single skill (that is skill-creator) and NOT for whole-config GC across hooks/permissions/MCP (that is config-gc).
license: MIT
metadata:
  author: shimo4228
  version: "2.0"
  extracted: "2026-02-21"
origin: shimo4228
---

# skill-stocktake — Skill Quality Audit

Evaluate installed skills **holistically, all in one context**, and assign each a
verdict: `Keep / Improve / Update / Retire / Merge`. This skill does NOT do the
improving — once it has a verdict, it **hands off to skill-creator (the improvement
engine)**. That boundary is the point: stocktake is the quality gate, skill-creator
is the fixer.

> Design note: the old version shelled out to scan scripts and split evaluation into
> ~20-skills-per-subagent batches. With a 1M context that is not just unnecessary but
> harmful — batching blinds each subagent to skills in the other batches, so it misses
> cross-skill overlap. Now we enumerate with Glob and read every skill into one context.
> Overlap detection depends on that single-context view.

## Modes (`$ARGUMENTS`)

| Argument | Behavior |
|----------|----------|
| none / `full` | Read and evaluate every skill (default) |
| `changed` | Re-evaluate only skills whose `SKILL.md` mtime is newer than `results.json`'s `evaluated_at`; carry the rest forward from the ledger |

`changed` detects changes inline (no script):
```bash
find ~/.claude/skills -name SKILL.md -newermt "$(jq -r .evaluated_at ~/.claude/skills/skill-stocktake/results.json)"
```

## Phase 1 — Inventory

Enumerate skill definition files with Glob (no script needed):

- `~/.claude/skills/*/SKILL.md`
- `~/.claude/skills/learned/*.md`
- if cwd has `.claude/skills/`, also `{cwd}/.claude/skills/*/SKILL.md` (project skills)

> Because Glob targets only `SKILL.md` / `learned/*.md`, dependency markdown under
> `.venv` or `.pytest_cache` is excluded structurally (no pruning required). The
> noise the old `find -name "*.md"` pulled in cannot occur.

**Usage counts**: read `~/.claude/metrics/skill-usage.jsonl` inline (the PostToolUse
hook `log-skill-usage.sh` appends to it — an independent measurement layer) and count
per-skill events over 7 / 30 / 90 days. Each line is JSON `{ts,event,skill,path,project}`;
count both `invoke` and `read` events. Aggregate with a throwaway `python3`/`jq` one-liner
rather than hand-counting — the log grows over time and hand-counting wastes a tool turn
per invocation.

- If the log is **missing or its first event is younger than 90 days**, render usage as
  `—` (unmeasured). **Never render it as 0** — unmeasured and unused are different facts.

State the scan result up front: which paths were scanned, how many skills found, and
whether usage is measurable.

## Phase 2 — Evaluation (fully inline, holistic)

Read the body of **every** target skill and evaluate them one by one while seeing the
whole set. Checklist:

- [ ] Content overlap with other skills (**a documented orchestrator/sub-skill split is NOT overlap** — e.g. paper-ecosystem → its reviewers, citation-sync → release-doi/wikidata. Distinguish intentional layering from genuine duplication)
- [ ] Overlap with MEMORY.md / CLAUDE.md / rules
- [ ] Freshness of technical references (if CLI flags / APIs / tool names look stale, confirm with WebSearch)
- [ ] Usage frequency (ignore it as a signal when unmeasured)

Evaluation is **holistic judgment, not a numeric rubric**. Guiding dimensions:
Actionability (concrete examples/steps you can act on), Scope fit (name, trigger, and
body aligned — not too broad or narrow), Uniqueness (not replaceable by MEMORY / another
skill), Currency (references work in the current environment).

| Verdict | Meaning |
|---------|---------|
| Keep | Useful, current, unique value |
| Improve | Worth keeping, but specific improvements needed |
| Update | Referenced technology is outdated (verify with WebSearch) |
| Retire | Low quality, stale, or cost-asymmetric |
| Merge into [X] | Substantial overlap with another skill; name the target |

**Zero-usage rule**: when the usage log's first event is **at least 90 days old** AND a
skill has `use_90d == 0`, it MUST be surfaced as a Retire candidate (the final call is
the user's). While the log is younger than 90 days this rule does not fire, and verdicts
fall back to holistic judgment alone.

Evaluation is **origin-blind**: do not branch on ECC / self-authored / auto-extracted.
The same checklist applies to every skill.

## Phase 3 — Summary

Render a table: `Skill | 7d | 90d | Verdict | Reason`.

## Phase 4 — Consolidation

- **Retire / Merge**: per file, present (1) the specific defect found, (2) what covers the
  same need instead (Retire: which existing skill/rule; Merge: the target and what content
  to integrate), (3) the impact of removal (dependent skills, MEMORY references). **Act only
  after the user confirms.**
- **Improve / Update**: **offer** to hand off — "Hand `<skill>` to skill-creator to improve?"
  — and on approval invoke `skill-creator` with the target skill. Stocktake never does the
  improvement work itself.
- **Update the ledger**: Read `results.json` → merge this run's verdicts → Write it back
  (`evaluated_at` = real UTC from `date -u +%Y-%m-%dT%H:%M:%SZ`). In `changed` mode, preserve
  the prior verdicts of skills you did not re-evaluate.
- If MEMORY.md exceeds 100 lines, propose compression.

## Reason quality (required)

Every `reason` must be **self-contained** — decision-enabling on its own. "unchanged" alone
is banned; always restate the evidence.

- **Retire**: state the defect + the replacement. Bad: `"Superseded"` / Good: `"disable-model-invocation: true already set; continuous-learning-v2 covers the same patterns plus confidence scoring. No unique content remains."`
- **Merge**: name the target + what to integrate. Bad: `"Overlaps with X"` / Good: `"42-line thin content; Step 4 of chatlog-to-article already covers this workflow. Integrate the 'article angle' tip there as a note."`
- **Improve**: which section, what change (target size if relevant). Bad: `"Too long"` / Good: `"276 lines; 'Framework Comparison' (L80–140) duplicates ai-era-architecture-principles. Delete it to reach ~150 lines."`
- **Keep** (mtime-only change in `changed` mode): restate the original rationale. Bad: `"Unchanged"` / Good: `"Content unchanged. Unique Python reference explicitly imported by rules/python/; no overlap."`

## results.json (lean ledger)

```json
{
  "evaluated_at": "2026-06-24T11:09:00Z",
  "skills": {
    "<skill-name>": {
      "path": "~/.claude/skills/<name>/SKILL.md",
      "verdict": "Keep",
      "reason": "...",
      "mtime": "2026-01-15T08:30:00Z"
    }
  }
}
```

A ledger for verdict history and the last-audit timestamp only. Update it inline with
Read/Write, not a script. Global skills only (project skills are read fresh from cwd, not
cached here).

## Related

- `skill-creator` — the improvement engine; hand off Improve/Update work to it.
- `config-gc` — GC over skill *existence* and the whole of ~/.claude (hooks/permissions/MCP/cache); stocktake judges skill *quality*.
- `harness-sync` — use it to sync this skill to its public repo.
- Usage measurement: `~/.claude/hooks/log-skill-usage.sh` → `~/.claude/metrics/skill-usage.jsonl` (a measurement layer independent of stocktake).

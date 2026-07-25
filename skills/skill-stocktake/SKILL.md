---
name: skill-stocktake
description: Audit installed Claude skills for quality and surface Keep/Improve/Update/Retire/Merge verdicts. Use when the user says "audit my skills", "stocktake", "review my skills", "which skills should I retire or merge", "do a quality pass over my skills", or "/skill-stocktake". NOT for creating or improving a single skill (that is skill-creator) and NOT for whole-config GC across hooks/permissions/MCP (that is config-gc).
license: MIT
metadata:
  author: shimo4228
  version: "3.0"
  extracted: "2026-02-21"
origin: shimo4228
---

# skill-stocktake — Skill Quality Audit

Evaluate installed skills and assign each a verdict: `Keep / Improve / Update / Retire /
Merge`, plus `Out of scope` for skills this harness does not own (Phase 0). This skill
does NOT do the improving — once it has a verdict, it **hands off to skill-creator (the
improvement engine)**. That boundary is the point: stocktake is the quality gate,
skill-creator is the fixer.

> Design note (v3.0). v1 batched ~20 skills per subagent with no cross-batch view —
> overlap was structurally invisible. v2.0 swung to everything-in-one-context on the
> 1M-context premise. A 2026-07-13 controlled comparison falsified half of that premise:
> the single-context pass had returned 84/84 Keep, while fresh-context batches with
> **unconditional** reference verification surfaced 12/73 non-Keep (half with
> deterministic evidence — 404 links, deleted files, retired CLI flags), and a dedicated
> overlap probe reproduced the set-level dimension *without* needing all bodies in one
> context (0 genuine duplications across 17 clusters, all documented layering).
> Two mechanisms explained the gap: (1) per-item attention dilutes as the context fills,
> and (2) a **conditional** verification trigger ("confirm if it looks stale") degrades
> to "never verify" in a loaded context, because the trigger itself is a diluting
> judgment. v3.0 is therefore a hybrid, split not by context length but by the property
> being checked (see when-code-when-llm): deterministic checks are code-owned and
> unconditional; per-item judgment gets narrow, dense contexts; set-level judgment gets
> a light description sweep with targeted deep reads.

## Modes (`$ARGUMENTS`)

| Argument | Behavior |
|----------|----------|
| none / `full` | Evaluate every skill (default) |
| `changed` | Re-evaluate only skills whose `SKILL.md` mtime is newer than `results.json`'s `evaluated_at`; carry the rest forward from the ledger. Phase 0 and Phase 3 still run over the full set (structural debt and overlap are set properties) |

`changed` detects changes inline (no script):
```bash
find ~/.claude/skills -name SKILL.md -newermt "$(jq -r .evaluated_at ~/.claude/skills/skill-stocktake/results.json)"
```

## Phase 0 — Structural pre-pass (deterministic, code-owned)

Run BEFORE any LLM judgment. These checks never ride on per-item attention:

1. **skill-health scan** — dangling references / missing artifacts across the library
   (run its scanner per `~/.claude/skills/skill-health/SKILL.md`). Mandatory, not
   optional: this is the structural layer of Curate (ADR-0019 layering), and the v2.2
   verification showed exactly these defects slipping through judgment-owned checks.
2. **Ledger hygiene** — for every `results.json` entry: the path must exist on disk and
   the key must follow the canonical rule below. Dedup violations (same path under two
   keys → keep `learned/<name>`, delete the bare key). Entries whose path no longer
   exists are removed (note them in the report as retired-from-disk).
3. **Existence before judgment** — a skill that fails the existence check never reaches
   Phase 2. Do not let an LLM assign Keep to a file that is not there (this happened:
   two nonexistent paths carried Keep verdicts in the 2026-07-05 ledger).
4. **Ownership before judgment** — the same skill-health run reports `external`: skills
   whose directory is a symlink out of the skills root (a package manager's tree, a
   sibling checkout). **These do not get an Improve/Update verdict.** Record them as
   `Out of scope` with the owner and real path in the reason, and route any real defect
   **upstream** (issue / PR). A verdict here is not actionable — an edit lands in
   someone else's tree, never reaches git, and disappears on their next upgrade.
   Live miss on 2026-07-25: `hunk-review` drew an Improve for a stale flag table and the
   fix was written into `/opt/homebrew/Cellar/hunk/0.17.1/…`; it was reverted and filed
   as [modem-dev/hunk#595](https://github.com/modem-dev/hunk/issues/595). The check is
   fully structural (`is_symlink()`), so it belongs in code, never in per-item attention.

## Phase 1 — Inventory

Enumerate skill definition files with Glob (no script needed):

- `~/.claude/skills/*/SKILL.md`
- `~/.claude/skills/learned/*.md`
- if cwd has `.claude/skills/`, also `{cwd}/.claude/skills/*/SKILL.md` (project skills)

**Canonical ledger keys**: a skill under `learned/` is keyed `learned/<name>` in
`results.json` — never bare `<name>`. A rule or skill referencing a learned note by
bare name does NOT make it a top-level skill.

**Usage counts** (parent-owned; batch agents never see them): read
`~/.claude/metrics/skill-usage.jsonl` inline (the hook `log-skill-usage.sh` appends to
it) and count per-skill events over 7 / 30 / 90 days. Aggregate with a throwaway
`python3`/`jq` one-liner.

- If the log is **missing or its first event is younger than 90 days**, render usage as
  `—` (unmeasured). **Never render it as 0** — unmeasured and unused are different facts.
- `slash` events exist only from **2026-07-03**. For windows straddling that date, treat
  counts for **user-invocable** skills as **lower bounds**, and never Retire on low
  usage alone when the skill's primary mode is user-typed slash invocation.

State the scan result up front: which paths were scanned, how many skills found, and
whether usage is measurable.

## Phase 2 — Per-item scrutiny (parallel small batches, fresh contexts)

Split the target set into batches of **10–12 files**, interleaving `learned/` notes
across batches, and launch **one subagent per batch in parallel**. Small batches are
the point: per-item attention dilutes as a context fills, and the 84/84-Keep failure
mode is exactly that dilution. Do NOT pass prior verdicts or the ledger to batch agents
(anchoring); do NOT pass usage data (parent-owned dimension).

Each batch agent applies, per skill:

**Stage 1 — binary screen.** Explicit Yes/No per item; surface only the No answers:

- [ ] Actionability: concrete steps/commands/examples you can act on?
- [ ] Scope fit: name, trigger (description), and body aligned — not too broad or narrow?
- [ ] Within-batch uniqueness: no content overlap with other skills in this batch?
  (a documented orchestrator/sub-skill split is NOT overlap; cross-batch overlap is
  Phase 3's job, not this agent's)
- [ ] Currency: **unconditionally verify** every artifact the skill names — `ls` each
  referenced path (`~/.claude/agents/<name>.md`, hooks, bundled scripts), run
  `--help` / version checks for named CLI flags, fetch named URLs. "Verify if it looks
  stale" is banned phrasing: the condition is what dilutes. Deterministically checkable
  claims get deterministic checks, every time.

**Stage 2 — verdict pressure-test (non-Keep candidates only).** Generate 1–3
skill-specific atomic yes/no questions that try to **refute the draft verdict** before
finalizing it. Answer each with one line of evidence (file read, path check, WebSearch).
A refuted defect → fall back toward Keep. A confirmed defect → the No answers become
the concrete improvement list handed to skill-creator (Improve/Update) or the removal
rationale (Retire).

Evaluation is **holistic judgment, not a numeric rubric** — binary answers are evidence
feeding the verdict, never aggregated into a score (a satisfaction ratio changes no
decision and dilutes a single dominant No). Batch agents return structured verdicts
with self-contained reasons; Keep-bound skills get no dynamic questions.

## Phase 3 — Overlap probe (one dedicated agent, set-level)

Cross-skill duplication is a set property; it gets a specialist, not a side effect.
One agent, whole library:

1. Read **name + description (+ heading structure)** of every target file — light pass.
2. Propose candidate overlap clusters greedily (false positives are fine at this stage).
3. For each candidate cluster, read the bodies side by side and judge:
   - `GENUINE_DUPLICATION` — removing one loses nothing; name the Merge target
   - `DOCUMENTED_LAYERING` — orchestrator→sub-skill, rule→skill, declared defer;
     quote the defer line as evidence
   - `ADJACENT_BUT_DISTINCT` — near domain, different job
4. One extra pass over `~/.claude/rules/` and MEMORY.md: is a rule re-stating a skill
   (or vice versa) beyond a declared pointer? Flag promotion residue (a learned note
   whose content a rule has fully absorbed) as Retire/Merge candidates.

Only `GENUINE_DUPLICATION` produces Merge verdicts. This probe is what replaces the
v2.0 "everything in one context" rationale — it recovers the set-level view at
description granularity plus targeted deep reads, without diluting Phase 2.

## Phase 4 — Synthesis (parent)

Merge Phase 2 verdicts, Phase 3 overlap verdicts, and parent-owned usage data:

- **Zero-usage rule**: when the usage log's first event is at least 90 days old AND a
  skill has `use_90d == 0`, surface it as a Retire candidate (final call is the user's).
  While the log is younger than 90 days this rule does not fire.
- **Aggregate cost (set-level)**: holding a skill is not free even when it is
  individually fine. Skill benefits are fragile — a large, uncurated library degrades
  skill selection and pulls behaviour back toward the no-skill baseline. The Keep bar
  **rises with library size**: when the set is large, a merely-adequate skill (rare
  use, low uniqueness, heavy adjacency) is a Retire/Merge candidate on
  aggregate-dilution grounds alone. A judgment input, never a quota.
- Conflicts (e.g. batch says Keep, probe says Merge) are resolved by the parent reading
  the cited evidence, not by vote.

| Verdict | Meaning |
|---------|---------|
| Keep | Useful, current, unique value |
| Improve | Worth keeping, but specific improvements needed |
| Update | Referenced technology/artifact is outdated (verified, with evidence) |
| Retire | Low quality, stale, or cost-asymmetric |
| Merge into [X] | Genuine duplication confirmed by the overlap probe; name the target |

Evaluation is **origin-blind**: the same checklist applies to every skill.

Render a table: `Skill | 7d | 90d | Verdict | Reason`.

## Phase 5 — Consolidation

**Confirm one by one** (config-gc's confirm-each design): walk the non-Keep candidates
sequentially — for each, show the evidence first, then ask `[y/n/skip]`. Never batch the
approval. The user can stop at any point; `skip` records the verdict in the ledger
unactioned.

- **Retire / Merge**: per file, present (1) the specific defect found, (2) what covers
  the same need instead, (3) the impact of removal (dependent skills, rule pointers,
  MEMORY references) → ask `[y/n/skip]`. **Act only after the user confirms that file.**
- **Improve / Update**: **offer** per skill — "Hand `<skill>` to skill-creator?
  `[y/n/skip]`" — and on approval invoke `skill-creator` with the target skill and the
  No-answer list. Stocktake never does the improvement work itself.
- **Update the ledger**: Read `results.json` → merge this run's verdicts → Write it back
  (`evaluated_at` = real UTC from `date -u +%Y-%m-%dT%H:%M:%SZ`). In `changed` mode,
  preserve the prior verdicts of skills you did not re-evaluate.
- If MEMORY.md exceeds 100 lines, propose compression.

## Reason quality (required)

Every `reason` must be **self-contained** — decision-enabling on its own. "unchanged"
alone is banned; always restate the evidence. For non-Keep verdicts, the reason cites
the **No answers from the binary screen / pressure-test** (question + one-line evidence).

- **Retire**: state the defect + the replacement. Bad: `"Superseded"` / Good:
  `"disable-model-invocation: true already set; continuous-learning-v2 covers the same
  patterns plus confidence scoring. No unique content remains."`
- **Merge**: name the target + what to integrate. Bad: `"Overlaps with X"` / Good:
  `"42-line thin content; Step 4 of chatlog-to-article already covers this workflow.
  Integrate the 'article angle' tip there as a note."`
- **Improve**: which section, what change. Bad: `"Too long"` / Good: `"276 lines;
  'Framework Comparison' (L80–140) duplicates ai-era-architecture-principles. Delete it
  to reach ~150 lines."`
- **Keep** (mtime-only change in `changed` mode): restate the original rationale.

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
Read/Write, not a script. Global skills only (project skills are read fresh from cwd,
not cached here). Phase 0's hygiene rules (canonical keys, existing paths) are part of
every write.

## Related

- `skill-creator` — the improvement engine; hand off Improve/Update work to it.
- `skill-health` — the deterministic structural layer; Phase 0 runs its scanner as a
  mandatory pre-pass (enumerate-then-decide: code enumerates debt, judgment decides).
- `config-gc` — GC over skill *existence* and the whole of ~/.claude; stocktake judges
  skill *quality*.
- `rules-stocktake` — the same audit for `~/.claude/rules/` (residency cost instead of
  usage).
- `repo-asset-stocktake` — the same stocktake pattern for a project repo's non-code
  assets.
- `when-code-when-llm` — the dividing line Phase 0/2/3 implement: deterministic checks
  are code-owned and unconditional; judgment is holistic and narrow-context.
- `llm-as-judge` — the generic judge design canon (binary screen → pressure-test →
  holistic named verdict, no aggregation); Phase 2 is its library-scale implementation.
- `harness-sync` — use it to sync this skill to its public repo.
- Usage measurement: `~/.claude/hooks/log-skill-usage.sh` →
  `~/.claude/metrics/skill-usage.jsonl` (a measurement layer independent of stocktake).

## References

The two-stage binary-question design (screen → verdict pressure-test, holistic verdict,
no score aggregation) follows the checklist-decomposition evaluation line: BinEval
"Ask, Don't Judge" ([arXiv:2606.27226](https://arxiv.org/abs/2606.27226)), CheckEval
(arXiv:2403.18771), TICK (arXiv:2410.03608). Scores are deliberately not adopted:
BinEval's own limitations show over-decomposition degrades correlation on holistic
quality dimensions, and a satisfaction ratio would dilute a single dominant No.

The v3.0 hybrid architecture (deterministic pre-pass → fresh-context batches with
unconditional verification → dedicated overlap probe) is grounded in a 2026-07-13
controlled comparison on this library (n=73): the v2.0 single-context pass returned
84/84 Keep while fresh-context batches surfaced 12/73 non-Keep (6 with deterministic
evidence) and a dedicated probe confirmed 0 genuine duplications — i.e. per-item
scrutiny dilutes in a loaded context, set-level judgment does not need one.

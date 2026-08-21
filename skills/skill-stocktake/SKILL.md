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
> being checked: deterministic checks are code-owned and
> unconditional; per-item judgment gets narrow, dense contexts; set-level judgment gets
> a light description sweep with targeted deep reads.

## Modes (`$ARGUMENTS`)

| Argument | Behavior |
|----------|----------|
| none / `full` | Evaluate every skill (default) |
| `changed` | Re-evaluate only skills whose `SKILL.md` mtime is newer than `results.json`'s `evaluated_at`; carry the rest forward from the ledger. Phase 0 and Phase 3 still run over the full set (structural debt, overlap, and contradiction are set properties) |

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
it) and count per-skill events over 7 / 30 / 90 days plus the last-used date. Aggregate
with a throwaway `python3`/`jq` one-liner.

Four corrections that decide whether the number means anything (the first three were
live defects found on 2026-08-15, the fourth on 2026-08-17):

- **Split by event type; never sum them.** `slash` = the user typed it. `invoke` = the
  model selected it. `read` = a file was opened, which carries no intent. Only
  `slash + invoke` is *deliberate use*. Summing all three makes a never-chosen skill
  look busy.
- **Exclude this audit's own reads.** Phase 2 opens every `SKILL.md`, so a run that
  counts `read` events marks the whole library as used *by having audited it*. Drop
  events from the current day (or from this run's window) before counting.
- **`slash` events exist only from 2026-07-03.** For windows straddling that date,
  treat counts for **user-invocable** skills as lower bounds.
- **Drop `sandbox: true` rows.** They are the trace of skill-comply's compliance test
  making a sandboxed child session call the skill — a synthetic scenario, not use.
  Counting them makes exactly the skills under compliance test look busy. The tag exists
  only from 2026-08-17 (`log-skill-usage.sh` schema comment); older rows carry no tag, so
  for windows reaching before that date also drop rows whose `project` is under
  `/tmp/skill-comply-sandbox` or `/private/tmp/skill-comply-sandbox` (e.g.
  `select(.sandbox != true and ((.project // "") | test("^(/private)?/tmp/skill-comply-sandbox(/|$)") | not))`).

If the log is **missing**, render usage as `—` (unmeasured). **Never render it as 0** —
unmeasured and unused are different facts. If the log is younger than the widest window,
say so and label that column with the log's real span rather than the nominal one.

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
  Phase 3's job, not this agent's — the same goes for contradictions with skills outside
  this batch)
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

## Phase 3 — Overlap and contradiction probe (one dedicated agent, set-level)

Duplication **and contradiction** are set properties; they get a specialist, not a side
effect. A per-item batch cannot see either — each agent reads only its own 10 files and
finds nothing wrong with any of them individually. One agent, whole library:

1. Read **name + description (+ heading structure)** of every target file — light pass.
2. Propose candidate clusters greedily (false positives are fine at this stage).
3. For each candidate cluster, read the bodies side by side and judge:
   - `GENUINE_DUPLICATION` — removing one loses nothing; name the Merge target
   - `CONTRADICTION` — two skills that can both load give **opposite instructions for the
     same situation**, or a sub-skill's content violates the canon it defers to. Quote
     both sides. See the contradiction checks below.
   - `DOCUMENTED_LAYERING` — orchestrator→sub-skill, rule→skill, declared defer;
     quote the defer line as evidence
   - `ADJACENT_BUT_DISTINCT` — near domain, different job
4. One extra pass over `~/.claude/rules/` and MEMORY.md: is a rule re-stating a skill
   (or vice versa) beyond a declared pointer? Flag promotion residue (a learned note
   whose content a rule has fully absorbed) as Retire/Merge candidates.

### Contradiction checks (a declared boundary is a claim, not evidence)

`DOCUMENTED_LAYERING` certifies "not duplicated". It does **not** certify "not
contradictory", and a quoted defer line is the start of the check, not the end. For every
cluster labelled `DOCUMENTED_LAYERING`, run all three:

- **Does the subordinate file comply with the canon it defers to?** Read the canonical
  file's rules and look for the subordinate stating a *different* rule for the same
  decision — especially **defaults** ("if the user gives no X, use Y"), which contradict
  quietly because they only fire in the unspecified case.
- **Is the defer bidirectional?** A one-directional defer (canon claims the subordinate,
  subordinate says nothing) means the subordinate **loads alone without its correction**
  whenever its own description wins the trigger. A broad description on a subordinate
  file turns a latent contradiction into an active one.
- **Do the two files presuppose the same author / project model?** Imported skills
  (`origin` = an external repo) carry their author's premises. A conflict of premises
  reads as a normal-looking instruction and survives every per-file check.

`GENUINE_DUPLICATION` produces Merge verdicts. `CONTRADICTION` produces Improve (add the
missing defer, delete the conflicting rule, narrow the trigger) or, when the premises
themselves clash and the subordinate never fires on its own, Retire-and-absorb — name
what must move before deletion.

> Worked case, 2026-08-15: `article-writing` (origin: ECC) defaulted to "operator-style
> voice" absent supplied examples, while `writing-ecosystem` — which declared itself its
> canon — mandates 発見調. The defer existed only on the canon side, so a direct fire of
> `article-writing` would have installed the opposing default alone. The probe had
> labelled the pair `DOCUMENTED_LAYERING` on the strength of the quoted defer line.
> Verdict: Retire-and-absorb. This section exists because that pass missed it.

## Phase 4 — Synthesis (parent)

Merge Phase 2 verdicts, Phase 3 overlap / contradiction verdicts, and parent-owned usage data:

- **Usage is rendered, never thresholded.** There is no zero-usage rule and no window
  that auto-nominates a skill. Put the deliberate-use counts and the last-used date in
  the table and let judgment read them. A threshold compresses the signal to one bit and
  throws away the part that decides the call — 2026-08-15: 21 of 65 skills had zero
  deliberate use, a list that would have been useless as candidates (it is mostly
  seasonal skills like `paper-deposit` and `release-doi`) but was highly informative
  read as numbers.
- **Compare observed cadence against the cadence the skill's own description implies.**
  A skill that should fire weekly and has not fired in a month is not unwanted — its
  **trigger is broken**, which is an Improve on the description, not a Retire. A skill
  that fires a few times a year and last fired at the last release is behaving
  correctly. Same number, opposite verdict; only the expected cadence separates them.
- **The Retire signal is a conjunction — all three, not any one.** Write it as an AND or
  it over-produces (measured below):
  1. **Zero deliberate use** over the log's real span.
  2. **Observed cadence contradicts the cadence the description implies** — the previous
     bullet. A seasonal skill sitting at zero between releases satisfies (1) and fails
     this one.
  3. **The defect is one of fit, not freshness.** A wrong scope, an unreachable trigger,
     or a niche another component is actually serving is a fit defect. A stale version
     pin or a dead pointer is a freshness defect — that is an Update, and it says nothing
     about whether the skill should exist.

  Worked measurement, 2026-08-15 (n=65). Condition (1) alone: 21 skills. (1) AND "has a
  confirmed defect", the loose form this bullet used to be written in: **9 skills** —
  including `paper-writing`, `paper-ecosystem` and `e2e`, all behaving correctly. Adding
  (2) and (3): **2 skills**.
  - `agent-architecture-audit` — its description claims "any LLM-powered feature", the
    widest trigger in the library, and it fired zero times in 66 days. Maximal claimed
    cadence against zero observed is the cleanest possible failure of (2).
  - `council` — `grill-me` took 46 deliberate uses in the same pre-build deliberation
    niche while `council` took zero, *and* `grill-me`'s body explicitly routes to it
    ("a clean choice between two known options → use `council`"). A declared handoff that
    never fires in 66 days means the receiving case does not arise on its own.

  Note what (3) excludes. Nine of today's Improve/Update verdicts were freshness defects
  found by the currency check; none of them bear on existence. Do not let a productive
  currency pass inflate the Retire list.
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
| Merge into [X] | Genuine duplication confirmed by the probe; name the target |
| Retire-and-absorb | A `CONTRADICTION` whose premises clash and whose subordinate never fires on its own; name what must move into the canon before deletion |

Evaluation is **origin-blind**: the same checklist applies to every skill.

Render a table: `Skill | 7d | 30d | 90d | last used | Verdict | Reason`, where the counts
are **deliberate use only** (`slash + invoke`). State the log's real span next to the
widest column.

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
- `agent-stocktake` — the third sibling, for `~/.claude/agents/` (hybrid cost model:
  description = residency, body = invocation).
- `generation-audit` — on a model-generation change, collects runtime-layer evidence
  (conflict / redundancy / drift) and hands the skills slice to Phase 4 synthesis as
  external evidence (read, never require).
- `harness-boundary` — design-time lens (layer / portability / obsolescence) for proposed
  mechanisms; applied to an installed skill, its Delete / Move are Phase 4 evidence only.
- `repo-asset-stocktake` — the same stocktake pattern for a project repo's non-code
  assets.
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

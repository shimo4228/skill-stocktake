Language: English | [日本語](README.ja.md)

# skill-stocktake

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shimo4228/skill-stocktake)

An [Agent Skill](https://agentskills.io/specification) for Claude Code that audits the skills installed under `~/.claude/skills/` (plus the current project's `.claude/skills/`) and proposes a verdict for each one, such as Keep, Improve, Update, Retire or Merge (the full list is under [Verdict Criteria](#verdict-criteria)). It combines a deterministic structural pre-pass (code checks that every script, file and path a skill names exists), per-skill scrutiny in small fresh-context batches, and a dedicated cross-skill overlap probe, and it reaches each verdict by holistic judgment, never a numeric score. Nothing is retired, merged or handed off for improvement until you confirm that skill. Skills installed through plugins are outside the scan. A run ends in one table with a row per skill and a reason that stands on its own; a Merge reason, for example, reads: "42-line thin content; Step 4 of chatlog-to-article already covers this workflow. Integrate the 'article angle' tip there as a note."

The audit checks every URL your skills name, once, from your machine, and starts one separate `claude -p` session for a cost report. That session and the parallel subagents that review your skills use your Claude usage. The author's other work is listed under [More from the author](#more-from-the-author).

## Install

skill-stocktake runs scripts from [skill-health](https://github.com/shimo4228/skill-health) (the structural scan and the URL check), and skill-health runs this skill's usage script, so install the two together. Both run their scripts with [`uv`](https://docs.astral.sh/uv/) and Python 3.11 or later.

There are two routes. Cloning (first block) installs the pair alone. The akc-cycle plugin (second block) installs both, plus `skill-creator`, which the audit hands Improve and Update verdicts to.

```bash
git clone https://github.com/shimo4228/skill-stocktake
git clone https://github.com/shimo4228/skill-health
mkdir -p ~/.claude/skills
cp -r skill-stocktake/skills/skill-stocktake skill-health/skills/skill-health ~/.claude/skills/
```

With the clone install, the skill calls its scripts at `~/.claude/skills/skill-stocktake` and `~/.claude/skills/skill-health`, so keep the folders at those paths. Then ask in plain words, such as "audit my skills", or type `/skill-stocktake`.

The same skill also ships in the [akc-cycle](https://github.com/shimo4228/akc-cycle) Claude Code plugin, together with the other skills of the Agent Knowledge Cycle (AKC: the author's six-phase, human-gated cycle that turns a coding agent's repeated experience into skills and rules). skill-stocktake belongs to the cycle's Curate phase, and in the plugin it is called `/akc-cycle:skill-stocktake`. This repository is synced one way from the same source, so between syncs it can trail the plugin.

```
/plugin marketplace add shimo4228/akc-cycle
/plugin install akc-cycle@akc-cycle
```

## Requirements

- Claude Code with the **Glob**, **Read**, **Write**, **Bash**, and **subagent (Task/Agent)** tools (the per-skill review batches and the overlap probe, Phases 2 and 3 in [How It Works](#how-it-works), run as parallel subagents).
- `uv` and Python 3.11 or later, and skill-health installed next to this skill (see Install).
- `jq` for `changed` mode, which compares file times against the last run.
- For the `ctx` column (the tokens each skill's listing line adds to every turn): Claude Code 2.1.269 or later (as of 2026-09-15), which prints the `/skill-doctor` report. When that report is unavailable, the column renders `—` (unmeasured).
- For the usage column (deliberate uses in the last 14 days, and the last-used date): a log at `~/.claude/metrics/skill-usage.jsonl`. The hook in this repo that would write it, `hooks/log-skill-usage.sh`, does not work yet, because the helper it loads, `hooks/_session-common.sh`, is not shipped. Without the log the audit still runs, and the column renders `—` (unmeasured), never 0.

## Modes

| Mode | Trigger | What it does |
|------|---------|--------------|
| **full** | default, or `/skill-stocktake full` | Read and evaluate every skill |
| **changed** | `/skill-stocktake changed` | Re-evaluate only skills whose `SKILL.md` changed since the last run; carry the rest forward from the verdict ledger (`results.json`, where each run's verdicts are kept). The structural pre-pass and the overlap probe (Phases 0 and 3 in [How It Works](#how-it-works)) still run over every skill |

## How It Works

1. **Phase 0 — Structural pre-pass (deterministic)**: run the [skill-health](https://github.com/shimo4228/skill-health) scanner for dangling references and missing artifacts, and check that each verdict-ledger entry is keyed by a skill's folder name and points to a path that exists. A ledger entry whose skill folder no longer exists never reaches judgment: it is removed from the ledger and listed in the report. Skills with dangling references still go on to judgment. A skill whose folder is a symlink into someone else's tree gets `Out of scope`, and any defect is reported upstream instead of edited.
2. **Phase 1 — Inventory**: Glob `~/.claude/skills/*/SKILL.md` (and project skills under `$PWD/.claude/skills/` if present). The parent session then collects three kinds of evidence once: usage from the bundled script (which renders `—` while no usage log exists, see [Requirements](#requirements)), the live/dead/blocked status of every URL the skills name (checked serially through skill-health), and the tokens each skill's listing line adds to every turn, from `claude -p "/skill-doctor"`.
3. **Phase 2 — Per-item scrutiny (parallel small batches)**: split into batches of 10–12 and launch one subagent per batch, each with a fresh context. Stage 1 is a per-skill Yes/No screen (actionability, scope fit, uniqueness within the batch, currency, body hygiene, instructions hidden in the description), and every named path and CLI flag is verified **unconditionally**. Every skill also answers two existence questions: would the library lose a job nothing else covers, and does the skill earn its selection, drift and maintenance cost? Stage 2 asks skill-specific refutation questions of any non-Keep draft verdict. The answers are evidence for one holistic verdict, never summed into a score, and batch agents never see prior verdicts or usage and cost data.
4. **Phase 3 — Overlap and contradiction probe (dedicated agent)**: one agent sweeps every skill's name + description, proposes candidate clusters greedily, then reads candidate bodies side by side to judge whether each cluster is a real duplicate, a job another asset already covers whole, a division of work the skills write down, two neighbouring but separate jobs, or a contradiction (two skills that can both load giving opposite instructions for the same situation). Only a real duplicate produces a Merge verdict, and only when the probe can name the content that should move into the target skill; a skill whose whole job is already covered, with nothing left to move, gets Retire.
5. **Phase 4 — Synthesis**: the parent merges batch verdicts, probe verdicts, usage and cost, and renders a per-skill table (`Skill | ctx | 14d | last used | Verdict | Reason`) with self-contained reasons. Content owns the verdict; usage is reference evidence, never a threshold or a veto.
6. **Phase 5 — Consolidation**: non-Keep candidates are confirmed **one by one**: evidence first, then `[y/n/skip]`, never bulk approval. Retire/Merge act only after you confirm that file; Improve/Update are offered per skill as a hand-off to a skill named `skill-creator`, the improvement engine; the author's [`skill-creator`](https://github.com/shimo4228/akc-cycle/tree/main/skills/skill-creator) ships in the akc-cycle plugin. The verdict ledger is updated inline.

## Verdict Criteria

| Verdict | Meaning |
|---------|---------|
| **Keep** | Useful, current, unique value |
| **Improve** | Worth keeping, but specific improvements needed |
| **Update** | Referenced technology or artifact is outdated (verified, with evidence) |
| **Retire** | Obsolete, not worth its selection, drift and maintenance cost, or fully covered by another asset with nothing left to move |
| **Merge into [X]** | Does the same job as another skill, with named content to move into it; names the target and what to move |
| **Retire-and-absorb** | Contradicts the skill it defers to and never fires on its own; names what must move before deletion |
| **Out of scope** | Owned by someone else's tree (a symlinked skill folder); defects go upstream |

## References

The audit's **aggregate-cost** dimension (what the library costs as a whole, beyond each skill) holds that a large, uncurated skill library degrades skill selection and pulls behaviour back toward the no-skill baseline, so the Keep bar rises with library size. It rests on 2026 empirical work on agent skill libraries:

- [How Well Do Agentic Skills Work in the Wild](https://arxiv.org/abs/2604.04323) (Liu et al., 2026) finds that skill benefits weaken in realistic settings as the agent must retrieve from a large, uncurated library.
- [SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks](https://arxiv.org/abs/2602.12670) (Li et al., 2026) finds that curation produces large, uneven gains across domains, and that skill quality has a non-linear effect on outcome.
- [SkillOps: Managing LLM Agent Skill Libraries as Self-Maintaining Software Ecosystems](https://arxiv.org/abs/2605.13716) (Pu, Song & Zhao, 2026) frames "skill technical debt" and library-health maintenance as a first-class discipline.

Where SkillOps frames library maintenance as a self-maintaining ecosystem, skill-stocktake keeps the *judgment of what stays* with the human. The audit proposes verdicts and you confirm them.

## More from the author

- **[Offloading AI's Weak Spots to Shell Scripts — Designing, Building, and Publishing a Skill Audit Command](https://dev.to/shimo4228/offloading-ais-weak-spots-to-shell-scripts-designing-building-and-publishing-a-skill-audit-2ll8)** ([日本語](https://zenn.dev/shimo4228/articles/skill-stocktake-design-journey)): how the first versions of this audit moved file listing and timestamps out of the model and into deterministic code after the model got them wrong from run to run.
- **[LLM-as-Judge Shouldn't Aggregate Scores: Binary Checks as Evidence, One Holistic Verdict](https://dev.to/shimo4228/llm-as-judge-shouldnt-aggregate-scores-binary-checks-as-evidence-one-holistic-verdict-822)** ([日本語](https://zenn.dev/shimo4228/articles/llm-judge-checks-not-scores)): why the audit answers yes/no questions as evidence for one named verdict, and the 73-skill re-audit that led to small fresh-context batches.
- **[akc-cycle](https://github.com/shimo4228/akc-cycle)**: installs this skill together with the rest of the cycle as one Claude Code plugin.
- **[Agent Knowledge Cycle](https://github.com/shimo4228/agent-knowledge-cycle)**: the reasoning behind each phase of the cycle, Curate among them, recorded as dated design decisions.
- **[skill-health](https://github.com/shimo4228/skill-health)**: the deterministic scan this audit runs first, which finds skills that name a script, file or sibling skill that does not exist; install it alongside.
- **[rules-stocktake](https://github.com/shimo4228/rules-stocktake)**: the same kind of audit for your always-loaded rules, weighing what each rule costs in every session.
- **[agent-stocktake](https://github.com/shimo4228/agent-stocktake)**: the same kind of audit for subagent definitions, whose descriptions ride in every session while their bodies load only when called.
- **[shimo4228](https://github.com/shimo4228/shimo4228)**: the author's hub, with AKC next to the other long-running practice lines and their DOIs.

## License

MIT

<details>
<summary>For tools and AI assistants</summary>

skill-stocktake is an Agent Skill for Claude Code that audits every skill under `~/.claude/skills/` and the current project's `.claude/skills/` (not plugin-installed skills) and proposes one verdict per skill, for people whose skill library has grown past what they can review by hand and who want stale, broken, overlapping or contradictory skills found with evidence. The verdicts are Keep, Improve, Update, Retire, Merge into [X] and Retire-and-absorb, plus Out of scope for skills symlinked in from someone else's tree. It deletes, merges or edits no skill file without a one-at-a-time confirmation; the verdict ledger is written on every run.

It exists because a large, uncurated skill library degrades skill selection, and because one context does not audit every item well. On the author's 73-skill library, the earlier version, which read every skill into one context, returned all Keep; small fresh-context batches surfaced 12 non-Keep verdicts, half with deterministic evidence, and a dedicated overlap probe kept the library-wide view without holding every body in one context. So the audit splits the work by the property checked: code for existence and references, narrow fresh contexts for per-skill quality, one agent for overlap and contradiction.

Canonical facts: MIT license; a `SKILL.md` plus one Python script, `skills/skill-stocktake/scripts/usage_stats.py` (Python 3.11 or later, standard library only, run through `uv` with the bundled `uv.lock`, tests under `skills/skill-stocktake/tests/`), and an optional Claude Code usage hook, `hooks/log-skill-usage.sh` (bash and `jq`, bats tests in `tests/log-skill-usage.bats`), which does not run yet because the helper it loads, `hooks/_session-common.sh`, is not shipped (it logs Skill-tool calls as `invoke`, typed `/skill` invocations as `slash` and Reads of skill `.md` files as `read`, and only `invoke` and `slash` count as deliberate use); maintained by one author (@shimo4228). Status: active, synced one way from the author's Claude Code harness by `scripts/sync-from-local.sh` (it never commits), and also shipped in the akc-cycle plugin as `/akc-cycle:skill-stocktake`, so this repository can trail the plugin between syncs. Requirements: Claude Code with Glob, Read, Write, Bash and subagents; `uv`; the skill-health skill installed at `~/.claude/skills/skill-health` (the two run each other's scripts); `jq` for `changed` mode; no paid key, but the parallel subagents and one `claude -p "/skill-doctor"` session use the operator's Claude usage, and every URL the skills name is fetched once, serially. It keeps a ledger at `~/.claude/skills/skill-stocktake/results.json`, deletes or edits skill files only after each confirmation, and hands Improve and Update verdicts to a skill named `skill-creator`.

Example: a full run first states which paths were scanned, how many skills were found, and whether usage and the listing-line token counts (`ctx`) were measurable. It then renders `Skill | ctx | 14d | last used | Verdict | Reason`, where `ctx` is the tokens the skill's listing line adds to every turn and `14d` counts deliberate uses (typed or model-invoked) in the last 14 days. A Merge reason reads: "42-line thin content; Step 4 of chatlog-to-article already covers this workflow. Integrate the 'article angle' tip there as a note." Each non-Keep verdict is then walked with its evidence and `[y/n/skip]`.

Links: [skills/skill-stocktake/SKILL.md](skills/skill-stocktake/SKILL.md) is the skill itself; [llms.txt](llms.txt) and [llms-full.txt](llms-full.txt) are the machine-readable summary and reference. The skill implements part of the Curate phase of the [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle), concept DOI [10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726); cite AKC by that DOI. The installable form of the whole cycle is [akc-cycle](https://github.com/shimo4228/akc-cycle).

</details>

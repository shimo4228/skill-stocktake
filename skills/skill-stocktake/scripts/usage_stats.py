"""Deterministic skill-usage aggregation for the stocktake audit (evidence, not a verdict).

Reads the JSONL written by `hooks/log-skill-usage.sh` and answers one question per
skill: **how many deliberate uses in the window, and when was the last one.** No
verdict — Keep / Improve / Retire stays with the fresh-context batch agents, and
usage is a parent-owned dimension those agents never see.

Four corrections decide whether the number means anything. They were prose in
`SKILL.md` and were re-derived as a jq one-liner on every audit; each is pinned by
a test in `tests/test_usage_stats.py`:

1. **Split by event type; never sum.** `slash` = the user typed it, `invoke` = the
   model selected it, `read` = a file was opened and carries no intent. Only
   `slash + invoke` is deliberate use. Measured 2026-08-26 against the real log
   (3060 rows): read=2055, invoke=813, slash=192 — summing would inflate every
   never-chosen skill several-fold.
2. **Drop `sandbox: true` rows** — the trace of skill-comply driving a sandboxed
   child session, a synthetic scenario rather than use.
3. **Drop untagged sandbox rows by `project` prefix.** The tag only exists from
   2026-08-17, so older rows carry the sandbox path and no tag. Measured
   2026-08-26: **0** rows carry the tag and **25** carry the path (2026-07-28 ..
   2026-08-17) — rule 2 alone currently filters nothing, and this rule is doing
   all the work. Five of those 25 fall in the trailing 14-day window, unevenly:
   `verify-bootstrap` reads as 2 uses uncorrected and **0** corrected. The
   correction is the only thing keeping a skill under compliance test from
   looking used.
4. **Report the real span when the log is younger than the window.** A 3-day log
   labelled "last 14 days" understates every skill.

Rule 3 has an expiry: once a 14-day window no longer reaches 2026-08-17 (from
2026-08-31) it stops matching *for the default window*. It stays unconditional
anyway because `--days` is caller-set and a `--days 90` audit still reaches those
rows; the prefix test is O(1) and, with the `/` boundary below, cannot over-match.
Delete it when the log itself no longer contains pre-2026-08-17 rows.

Boundary matching for rules 2-3 mirrors the writer hook: strip one leading
`/private` (macOS resolves `/tmp` through it) and require a `/` boundary, so a
lookalike such as `/tmp/skill-comply-sandbox-notes` is *not* swallowed —
over-matching erases real use, the more expensive error of the two.

Contract: JSON on stdout, always exit 0, no network, no writes. A missing or empty
log yields `measurable: false` and an empty `counts`; consumers must render that
as `—` (unmeasured), never as 0 — unmeasured and unused are different facts.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable, Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

DEFAULT_LOG = Path.home() / ".claude" / "metrics" / "skill-usage.jsonl"
DEFAULT_DAYS = 14
DELIBERATE_EVENTS = ("slash", "invoke")
# Value canon is skills/skill-comply/scripts/runner.py `SANDBOX_BASE`; the writer
# hook (hooks/log-skill-usage.sh) carries the same constant for the tag it emits.
SANDBOX_BASE = "/tmp/skill-comply-sandbox"


def _utc(moment: datetime) -> str:
    """Render as UTC. Formatting a `+09:00` row with a literal `Z` is nine hours wrong."""
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_ts(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    # `fromisoformat` happily returns a naive datetime for `2026-08-20T00:00:00` — the
    # obvious thing to type at `--now` — and comparing that to an aware log row raises,
    # breaking the "always exit 0" contract. Read a missing offset as UTC, which is what
    # the writer hook emits (`date -u`).
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def is_sandbox_path(project: object) -> bool:
    """True when *project* is the skill-comply sandbox base or lives under it."""
    if not isinstance(project, str):
        return False
    path = project.removeprefix("/private")
    return path == SANDBOX_BASE or path.startswith(SANDBOX_BASE + "/")


def aggregate(
    rows: Iterable[dict], *, now: str, days: int = DEFAULT_DAYS, malformed: int = 0
) -> dict:
    """Aggregate already-parsed rows in one pass.

    Takes an iterable, not a list: the log is walked exactly once and nothing here
    indexes or re-reads it, so `collect` can stream the file instead of materializing
    it. Pure otherwise — no IO — so the four rules stay testable on plain lists.
    """
    end = _parse_ts(now) or datetime.now(UTC)
    start = end - timedelta(days=days)

    excluded = {
        "read_events": 0,
        "sandbox_tagged": 0,
        "sandbox_path": 0,
        "out_of_window": 0,
        "malformed": malformed,
    }
    # Counters only. `last_used` is a *string rendering* of `last_seen`, so keeping it
    # in here made the value type `int | str | None` and `entry[event] += 1` a type
    # error waiting to happen (ty, 2026-08-28). It is joined back in at output time,
    # where the JSON shape is assembled — the emitted shape is unchanged.
    counts: dict[str, dict[str, int]] = {}
    # `last_used` is deliberately **not** window-scoped: "last deliberately used" is a
    # fact about the log, and clipping it to the window makes a skill used 30 days ago
    # byte-identical to one that was only ever read. The window bounds the count; the
    # date answers "when", which is what a retire decision turns on.
    last_seen: dict[str, datetime | None] = {}
    span_first: datetime | None = None
    span_last: datetime | None = None

    for raw in rows:
        ts = _parse_ts(raw.get("ts"))
        skill = raw.get("skill")
        if ts is None or not isinstance(skill, str) or not skill:
            excluded["malformed"] += 1
            continue
        if span_first is None or ts < span_first:
            span_first = ts
        if span_last is None or ts > span_last:
            span_last = ts
        # A skill seen only in excluded rows still gets an entry with 0. Dropping it
        # would make "present in the log but never deliberately chosen" — the exact
        # finding a stocktake wants — indistinguishable from "not in the log".
        # get-then-insert, not setdefault: this is the hottest line in the loop and
        # setdefault would allocate a throwaway dict on every row (95.7% of them, at
        # 3062 rows over 133 skills).
        entry = counts.get(skill)
        if entry is None:
            counts[skill] = entry = {"deliberate": 0, "slash": 0, "invoke": 0}
            last_seen[skill] = None

        # Precedence matters: a sandboxed `read` is sandbox noise, not a read event.
        if raw.get("sandbox") is True:
            excluded["sandbox_tagged"] += 1
            continue
        if is_sandbox_path(raw.get("project")):
            excluded["sandbox_path"] += 1
            continue
        event = raw.get("event")
        if event not in DELIBERATE_EVENTS:
            if event == "read":
                excluded["read_events"] += 1
            continue
        # Compared as datetimes, not raw strings: `fromisoformat` accepts `+09:00`
        # as readily as `Z`, and those two sort wrong against each other lexically.
        previous = last_seen[skill]
        if previous is None or ts > previous:
            last_seen[skill] = ts

        if ts < start or ts > end:
            excluded["out_of_window"] += 1
            continue

        entry["deliberate"] += 1
        entry[event] += 1

    span_days = (span_last - span_first).days if span_first and span_last else 0
    shorter = span_first is not None and span_days < days
    if shorter:
        window_label = (
            f"{span_first:%Y-%m-%d} .. {span_last:%Y-%m-%d} "
            f"({span_days}d, log younger than {days}d window)"
        )
    else:
        window_label = f"last {days}d"

    ordered = {
        skill: {**entry, "last_used": _utc(seen) if (seen := last_seen[skill]) else None}
        for skill, entry in sorted(counts.items(), key=lambda kv: (-kv[1]["deliberate"], kv[0]))
    }
    return {
        "window_days": days,
        "window_start": _utc(start),
        "window_end": _utc(end),
        "window_label": window_label,
        "span_shorter_than_window": shorter,
        "log_span": {
            "first": _utc(span_first) if span_first else None,
            "last": _utc(span_last) if span_last else None,
            "days": span_days,
        },
        "counts": ordered,
        "excluded": excluded,
    }


def collect(log: Path, *, now: str, days: int = DEFAULT_DAYS) -> dict:
    """Read *log* and aggregate it. A missing or unreadable log is unmeasured, not zero.

    The file is streamed line by line rather than read whole: the log is append-only
    and already ~650KB / 3060 rows, and holding the text, its split lines and every
    parsed row at once costs ~26x the memory of a single pass for no benefit.
    """
    tally: dict[str, Any] = {"malformed": 0, "rows": 0, "error": None}

    def stream() -> Iterator[dict]:
        try:
            # newline="\n" pins the line boundary to what the writer emits (`jq -c`
            # appends "\n"). Universal-newline mode would also break on a lone \r, and
            # `splitlines()` additionally on U+0085 / U+2028 / U+2029 — a `project` path
            # is the session cwd, untrusted input, and one such character would split a
            # real row into two malformed fragments (same reasoning as
            # `scripts/claims.py` read_events).
            handle = log.open(encoding="utf-8", newline="\n")
        except FileNotFoundError:
            return  # never written — the expected absence, already carried by `measurable`
        except OSError as exc:
            # A permission error otherwise renders byte-identical to "the hook was
            # never installed", and the reader reinstalls the hook forever.
            tally["error"] = f"{type(exc).__name__}: {exc}"
            return
        with handle:
            # Decoding happens during iteration, not at open(), so an invalid byte
            # raises here — past the open-time handler and past the JSON handler.
            # A corrupted log crashed the command instead of reporting itself.
            try:
                for line in handle:
                    if not line.strip():
                        continue
                    try:
                        parsed = json.loads(line)
                    except json.JSONDecodeError:
                        tally["malformed"] += 1
                        continue
                    if isinstance(parsed, dict):
                        tally["rows"] += 1
                        yield parsed
                    else:
                        tally["malformed"] += 1
            except UnicodeDecodeError as exc:
                tally["error"] = f"{type(exc).__name__}: {exc}"

    out = aggregate(stream(), now=now, days=days)
    # Unparseable lines are only known once the stream is exhausted, so they are added
    # after the walk rather than passed in.
    out["excluded"]["malformed"] += tally["malformed"]
    # `counts` is built only from rows, so an empty log already yields `{}` — no guard
    # needed. `measurable` counts rows that survived parsing, not rows that were read:
    # a writer-hook schema regression yields 300 rows that all land in `malformed`, and
    # `measurable: true` with an empty `counts` licenses the consumer to render 0 for
    # every skill — straight into mass Retire verdicts.
    usable = len(out["counts"]) > 0
    if tally["error"]:
        print(f"usage_stats: cannot read {log}: {tally['error']}", file=sys.stderr)
    return {"log": str(log), "log_error": tally["error"], "measurable": usable, **out}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Skill usage evidence (JSON, no verdict).")
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG, help="skill-usage.jsonl path")
    parser.add_argument("--days", type=int, default=DEFAULT_DAYS, help="window length in days")
    parser.add_argument(
        "--now",
        default=None,
        help="window end as ISO-8601 (default: now, UTC). A fixed clock keeps runs reproducible.",
    )
    args = parser.parse_args(argv)
    if args.now and _parse_ts(args.now) is None:
        # Falling back to wall-clock time here would defeat the one thing the flag is
        # for, and only be detectable by comparing `window_end` against what was passed.
        parser.error(f"--now is not ISO-8601: {args.now!r}")
    now = args.now or _utc(datetime.now(UTC))
    print(json.dumps(collect(args.log, now=now, days=args.days), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

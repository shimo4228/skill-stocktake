"""Regression tests for the four usage-aggregation corrections.

Each correction was prose in SKILL.md L76-102 and was re-implemented as a jq
one-liner on every stocktake. The numbers below come from the real log
(~/.claude/metrics/skill-usage.jsonl, 3060 rows, measured 2026-08-26) — see the
module docstring of scripts/usage_stats.py for the measurement.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

from scripts import usage_stats

NOW = "2026-08-26T13:51:25Z"


def row(ts, event, skill, project="/Users/x/repo", **extra):
    r = {"ts": ts, "event": event, "skill": skill, "path": "", "project": project, "session": ""}
    r.update(extra)
    return r


def write_log(tmp_path: Path, rows) -> Path:
    p = tmp_path / "skill-usage.jsonl"
    p.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return p


# -- correction 1: split by event type, never sum -----------------------------


def test_read_events_are_not_deliberate_use():
    """`read` carries no intent — summing it makes a never-chosen skill look busy."""
    rows = [
        row("2026-08-20T00:00:00Z", "read", "alpha"),
        row("2026-08-20T00:00:01Z", "read", "alpha"),
        row("2026-08-20T00:00:02Z", "slash", "alpha"),
        row("2026-08-20T00:00:03Z", "invoke", "alpha"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["alpha"]["deliberate"] == 2
    assert out["counts"]["alpha"]["slash"] == 1
    assert out["counts"]["alpha"]["invoke"] == 1
    assert "read" not in out["counts"]["alpha"]
    assert out["excluded"]["read_events"] == 2


def test_a_read_only_skill_reports_zero_deliberate_not_absent():
    """A skill that was only ever read must be visible with 0, not silently dropped."""
    rows = [row("2026-08-20T00:00:00Z", "read", "onlyread")]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["onlyread"]["deliberate"] == 0
    assert out["counts"]["onlyread"]["last_used"] is None


# -- correction 2 + 3: sandbox rows ------------------------------------------


def test_sandbox_tagged_rows_are_dropped():
    rows = [
        row("2026-08-20T00:00:00Z", "invoke", "beta"),
        row("2026-08-20T00:00:01Z", "invoke", "beta", sandbox=True),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["beta"]["deliberate"] == 1
    assert out["excluded"]["sandbox_tagged"] == 1


@pytest.mark.parametrize(
    "project",
    [
        "/tmp/skill-comply-sandbox",
        "/tmp/skill-comply-sandbox/run-1",
        "/private/tmp/skill-comply-sandbox",
        "/private/tmp/skill-comply-sandbox/run-1/x",
    ],
)
def test_untagged_sandbox_paths_are_dropped(project):
    """The tag only exists from 2026-08-17; 25 older rows carry the path but no tag."""
    rows = [row("2026-08-10T00:00:00Z", "invoke", "gamma", project=project)]
    out = usage_stats.aggregate(rows, now=NOW, days=30)
    assert out["counts"]["gamma"]["deliberate"] == 0
    assert out["excluded"]["sandbox_path"] == 1


@pytest.mark.parametrize(
    "project",
    [
        "/tmp/skill-comply-sandbox-notes",
        "/tmp/skill-comply-sandboxes",
        "/var/tmp/skill-comply-sandbox",
    ],
)
def test_lookalike_paths_are_not_dropped(project):
    """Boundary is `/` — swallowing `…-sandbox-notes` erases real use."""
    rows = [row("2026-08-20T00:00:00Z", "invoke", "delta", project=project)]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["delta"]["deliberate"] == 1
    assert out["excluded"]["sandbox_path"] == 0


# -- correction 4: window vs. real log span -----------------------------------


def test_span_shorter_than_window_is_reported():
    rows = [
        row("2026-08-24T00:00:00Z", "invoke", "eps"),
        row("2026-08-26T00:00:00Z", "invoke", "eps"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["span_shorter_than_window"] is True
    assert out["log_span"]["first"] == "2026-08-24T00:00:00Z"
    assert out["log_span"]["last"] == "2026-08-26T00:00:00Z"
    assert out["log_span"]["days"] == 2
    assert out["window_label"] == "2026-08-24 .. 2026-08-26 (2d, log younger than 14d window)"


def test_span_longer_than_window_uses_nominal_label():
    rows = [
        row("2026-06-10T22:40:35Z", "invoke", "eps"),
        row("2026-08-26T00:00:00Z", "invoke", "eps"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["span_shorter_than_window"] is False
    assert out["window_label"] == "last 14d"
    # only the in-window row counts
    assert out["counts"]["eps"]["deliberate"] == 1
    assert out["excluded"]["out_of_window"] == 1


# -- unmeasured vs. unused ----------------------------------------------------


def test_naive_now_does_not_crash(tmp_path):
    """`--now 2026-08-20` is the obvious thing to type; comparing it to an aware row
    raised and broke the always-exit-0 contract."""
    rows = [row("2026-08-20T00:00:00Z", "invoke", "iota")]
    out = usage_stats.aggregate(rows, now="2026-08-21T00:00:00", days=14)
    assert out["counts"]["iota"]["deliberate"] == 1
    assert out["window_end"] == "2026-08-21T00:00:00Z"


def test_offset_timestamps_render_as_utc():
    """A `+09:00` row stamped with a literal `Z` is nine hours wrong."""
    rows = [row("2026-08-20T09:00:00+09:00", "invoke", "kappa")]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["kappa"]["last_used"] == "2026-08-20T00:00:00Z"


def test_unparseable_now_is_rejected_rather_than_silently_ignored(tmp_path):
    with pytest.raises(SystemExit):
        usage_stats.main(["--log", str(tmp_path / "x.jsonl"), "--now", "yesterday"])


def test_all_rows_malformed_is_unmeasured_not_zero(tmp_path):
    """A writer-hook schema regression yields rows that all fail parsing; rendering
    that as 0 for every skill walks straight into mass Retire verdicts."""
    p = tmp_path / "skill-usage.jsonl"
    p.write_text('{"skill_name": "a", "event": "invoke"}\n' * 5, encoding="utf-8")
    out = usage_stats.collect(p, now=NOW, days=14)
    assert out["measurable"] is False
    assert out["excluded"]["malformed"] == 5


def test_unreadable_log_is_distinguishable_from_a_missing_one(tmp_path):
    p = tmp_path / "skill-usage.jsonl"
    p.write_text("{}\n", encoding="utf-8")
    p.chmod(0o000)
    try:
        out = usage_stats.collect(p, now=NOW, days=14)
    finally:
        p.chmod(0o600)
    assert out["measurable"] is False
    assert out["log_error"] and "Error" in out["log_error"]
    assert usage_stats.collect(tmp_path / "nope.jsonl", now=NOW, days=14)["log_error"] is None


def test_undecodable_log_is_reported_not_fatal(tmp_path):
    """Decoding happens during iteration, past both the open-time and JSON handlers."""
    p = tmp_path / "skill-usage.jsonl"
    p.write_bytes(b'{"ts":"2026-08-20T00:00:00Z","event":"invoke","skill":"a"}\n\xff\xfe\n')
    out = usage_stats.collect(p, now=NOW, days=14)
    assert out["log_error"] and "UnicodeDecodeError" in out["log_error"]
    # Text decoding is buffered, so rows before the bad byte are lost too — which is
    # why the failure has to be visible rather than rendered as "nothing was used".
    assert out["measurable"] is False


def test_missing_log_is_unmeasured_not_zero(tmp_path):
    out = usage_stats.collect(tmp_path / "nope.jsonl", now=NOW, days=14)
    assert out["measurable"] is False
    assert out["counts"] == {}


def test_empty_log_is_unmeasured_not_zero(tmp_path):
    p = tmp_path / "skill-usage.jsonl"
    p.write_text("", encoding="utf-8")
    out = usage_stats.collect(p, now=NOW, days=14)
    assert out["measurable"] is False
    assert out["counts"] == {}


# -- robustness ---------------------------------------------------------------


def test_malformed_lines_are_counted_not_fatal(tmp_path):
    p = tmp_path / "skill-usage.jsonl"
    p.write_text(
        json.dumps(row("2026-08-20T00:00:00Z", "invoke", "zeta"))
        + "\nnot json\n"
        + json.dumps({"ts": "garbage", "event": "invoke", "skill": "zeta"})
        + "\n",
        encoding="utf-8",
    )
    out = usage_stats.collect(p, now=NOW, days=14)
    assert out["measurable"] is True
    assert out["counts"]["zeta"]["deliberate"] == 1
    assert out["excluded"]["malformed"] == 2


def test_last_used_is_the_max_deliberate_ts():
    rows = [
        row("2026-08-20T00:00:00Z", "invoke", "eta"),
        row("2026-08-25T00:00:00Z", "slash", "eta"),
        row("2026-08-26T00:00:00Z", "read", "eta"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["eta"]["last_used"] == "2026-08-25T00:00:00Z"


def test_last_used_survives_the_window_cut():
    """ "Used 30 days ago" and "never deliberately used" must not render identically."""
    rows = [row("2026-07-20T00:00:00Z", "invoke", "stale")]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["stale"]["deliberate"] == 0
    assert out["counts"]["stale"]["last_used"] == "2026-07-20T00:00:00Z"
    assert out["excluded"]["out_of_window"] == 1


def test_last_used_compares_offsets_not_strings():
    """`+09:00` sorts before `Z` lexically and after it in time."""
    rows = [
        row("2026-08-20T09:00:00+09:00", "invoke", "tz"),
        row("2026-08-20T00:30:00Z", "invoke", "tz"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert out["counts"]["tz"]["last_used"] == "2026-08-20T00:30:00Z"


def test_sandbox_base_agrees_with_skill_comply_runner():
    """The third copy of this constant. tests/log-skill-usage.bats pins the other two;
    a one-sided move would leave this module silently un-filtering."""
    runner = (
        Path(__file__).resolve().parents[2] / "skill-comply" / "scripts" / "runner.py"
    ).read_text(encoding="utf-8")
    canon = re.search(r'^SANDBOX_BASE = Path\("(.*)"\)$', runner, re.MULTILINE)
    assert canon, "runner.py no longer declares SANDBOX_BASE in the pinned form"
    assert usage_stats.SANDBOX_BASE == canon.group(1)


def test_counts_are_sorted_by_deliberate_descending():
    rows = [
        row("2026-08-20T00:00:00Z", "invoke", "low"),
        row("2026-08-20T00:00:01Z", "invoke", "high"),
        row("2026-08-20T00:00:02Z", "invoke", "high"),
    ]
    out = usage_stats.aggregate(rows, now=NOW, days=14)
    assert list(out["counts"]) == ["high", "low"]


# -- CLI contract: evidence mode ---------------------------------------------


def test_cli_emits_json_and_exits_zero(tmp_path, capsys):
    log = write_log(tmp_path, [row("2026-08-20T00:00:00Z", "invoke", "theta")])
    assert usage_stats.main(["--log", str(log), "--now", NOW]) == 0
    data = json.loads(capsys.readouterr().out)
    assert data["counts"]["theta"]["deliberate"] == 1


def test_cli_exits_zero_on_missing_log(tmp_path, capsys):
    assert usage_stats.main(["--log", str(tmp_path / "nope.jsonl")]) == 0
    assert json.loads(capsys.readouterr().out)["measurable"] is False


@pytest.mark.integration
def test_module_entrypoint_exits_zero(tmp_path):
    """The `python -m` path the SKILL documents — the one thing main([...]) cannot cover."""
    log = write_log(tmp_path, [row("2026-08-20T00:00:00Z", "invoke", "theta")])
    proc = subprocess.run(
        [sys.executable, "-m", "scripts.usage_stats", "--log", str(log), "--now", NOW],
        capture_output=True,
        check=False,
        text=True,
        cwd=Path(__file__).resolve().parents[1],
    )
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["counts"]["theta"]["deliberate"] == 1

#!/usr/bin/env bash
# log-skill-usage.sh — skill usage measurement hook.
# Wired twice in settings.json:
#   - PostToolUse (matcher: Read|Skill)
#   - UserPromptSubmit (no matcher)
# Appends one JSONL line per skill usage event to ~/.claude/metrics/skill-usage.jsonl.
#
# Consumer-independent measurement layer: consumers (skill-stocktake など)
# はこのファイルを読むだけで、計測自体はどの consumer にも依存しない。
# Consumers MUST treat a missing log as "unmeasured", never as zero usage.
#
# Schema: {"ts": "...Z", "event": "invoke"|"read"|"slash", "skill": "...", "path": "...", "project": "..."}
#   - invoke: Skill tool による明示呼び出し (path は解決できた場合のみ)
#   - read:   .claude/skills/ 配下の .md の Read (description トリガー・参照読みを含む)
#   - slash:  ユーザーが /<skill> とタイプした起動 (UserPromptSubmit で捕捉)。
#             command-message 注入経路は Skill tool も Read も発生させないため、
#             この event が無いと user-invocable skill は系統的に過小計上される
#             (2026-07-03 追加)。ローカルに解決できた skill 名のみ記録する —
#             built-in コマンド (/model 等) や plugin skill (name に ":") は対象外。
#
# Environment:
#   SKILL_USAGE_LOG         Override log path (for bats tests only)
#   SKILL_USAGE_SKILLS_DIR  Override global skills dir (for bats tests only)

set -uo pipefail

INPUT=$(cat)
LOG="${SKILL_USAGE_LOG:-$HOME/.claude/metrics/skill-usage.jsonl}"
SKILLS_DIR="${SKILL_USAGE_SKILLS_DIR:-$HOME/.claude/skills}"

# A measurement hook must never break the session: any parse failure exits 0.
tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

emit() { # emit <event> <skill> <path>
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  jq -cn --arg ts "$ts" --arg event "$1" --arg skill "$2" --arg path "$3" --arg project "$cwd" \
    '{ts:$ts,event:$event,skill:$skill,path:$path,project:$project}' >> "$LOG" 2>/dev/null || true
}

# resolve_skill <name> — echo the canonical SKILL.md path, or nothing.
# Checks global skills dir, then the project-level .claude/skills of cwd.
resolve_skill() {
  local name="$1" cand
  for cand in "$SKILLS_DIR/$name/SKILL.md" "$SKILLS_DIR/$name.md" \
              "$cwd/.claude/skills/$name/SKILL.md" "$cwd/.claude/skills/$name.md"; do
    if [[ -f "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}

case "$tool" in
  Read)
    fp=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
    case "$fp" in
      */.claude/skills/*.md)
        rel="${fp##*/.claude/skills/}"
        # skill label: top directory for dir-style skills, basename for single-file skills.
        # `path` is the canonical join key for consumers; `skill` is a coarse label.
        if [[ "$rel" == */* ]]; then skill="${rel%%/*}"; else skill="${rel%.md}"; fi
        emit "read" "$skill" "$fp"
        ;;
    esac
    ;;
  Skill)
    name=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null) || exit 0
    [[ -n "$name" ]] || exit 0
    # Resolve canonical path so per-file aggregation works; plugin skills resolve to "".
    p=$(resolve_skill "$name") || p=""
    emit "invoke" "$name" "$p"
    ;;
  "")
    # No tool_name → possibly a UserPromptSubmit payload (user-typed /skill).
    event_name=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null) || exit 0
    [[ "$event_name" == "UserPromptSubmit" ]] || exit 0
    prompt=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
    [[ "$prompt" == /* ]] || exit 0
    name="${prompt#/}"
    name="${name%%[[:space:]]*}"
    # Local skill names only (kebab/underscore). Excludes plugin-namespaced
    # names (":") structurally; built-ins are excluded by failing to resolve.
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || exit 0
    if p=$(resolve_skill "$name"); then
      emit "slash" "$name" "$p"
    fi
    ;;
esac

exit 0

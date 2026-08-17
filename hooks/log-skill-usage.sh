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
# Schema: {"ts": "...Z", "event": "invoke"|"read"|"slash", "skill": "...", "path": "...",
#          "project": "...", "session": "...", "sandbox": true (省略可)}
#   - invoke: Skill tool による明示呼び出し (path は解決できた場合のみ)
#   - read:   .claude/skills/ 配下の .md の Read (description トリガー・参照読みを含む)
#   - slash:  ユーザーが /<skill> とタイプした起動 (UserPromptSubmit で捕捉)。
#             command-message 注入経路は Skill tool も Read も発生させないため、
#             この event が無いと user-invocable skill は系統的に過小計上される
#             (2026-07-03 追加)。ローカルに解決できた skill 名のみ記録する —
#             built-in コマンド (/model 等) や plugin skill (name に ":") は対象外。
#   - session: この event を出したセッションの識別子 (2026-08-15 追加、既存行には無い)。
#             consumer が「同一セッション / 同一 chain の中で走ったか」を問えるようにする
#             ためのもので、順序の判定 (simplify-order-notice.sh) がこれに依存する。
#             取れなければ "" — consumer は "" を「同一セッション」と読んではならない。
#             同じログには ~/.codex/hooks/ の双子 writer も書いており、そちらは session を
#             出さない。consumer は session 欠落行を「別セッション」として扱うこと。
#   - sandbox: cwd が skill-comply の sandbox 配下だった event (2026-08-17 追加)。
#             合成シナリオの skill 使用を本物の使用から分けるための tag で、行は落とさない —
#             除外は読み手の判断に属する。**この日より前の行には sandbox 行でも付かない**
#             (追加時点で 25 行の該当実績がある)。`select(.sandbox != true)` だけで濾すと
#             その窓の汚染がそのまま残るので、過去窓は `project` の prefix で併せて濾すこと。
#             tag を出す側に置くのは、境界の規則 (どこからが sandbox か) を consumer ごとに
#             複製させないため。値そのものは project から導出できる。
#
# Environment:
#   SKILL_USAGE_LOG         Override log path (for bats tests only)
#   SKILL_USAGE_SKILLS_DIR  Override global skills dir (for bats tests only)

set -uo pipefail

# shellcheck source=hooks/_session-common.sh
source "${BASH_SOURCE[0]%/*}/_session-common.sh" || exit 0

INPUT=$(cat)
LOG="${SKILL_USAGE_LOG:-$HOME/.claude/metrics/skill-usage.jsonl}"
SKILLS_DIR="${SKILL_USAGE_SKILLS_DIR:-$HOME/.claude/skills}"

# skill-comply の子セッションは sandbox を cwd にして走る。その skill 使用は合成シナリオ
# であって人間の使用ではないので、compliance 比のような指標を汚す（S2 実測: 同じ比が
# sandbox 込み 0.750 / 除外 0.857）。ここでは行を落とさず tag だけ足す — 落とすと既存の
# 集計の分母が黙って変わるし、除外は読み手の判断に属する。
# 値の正本は skills/skill-comply/scripts/runner.py の `SANDBOX_BASE`（複製の理由と検知は
# そちらのコメント）。
SKILL_COMPLY_SANDBOX_BASE="/tmp/skill-comply-sandbox"

# A measurement hook must never break the session: any parse failure exits 0.
# scalar は 1 フィールド 1 jq で取る。まとめ取り（1 本の jq + read での分割）は
# 区切り文字の問題が構造的に解けない: タブは IFS whitespace なので空フィールドが落ちて
# 値が 1 つ隣へずれ、SOH は macOS の bash 3.2 が分割せず、改行は cwd に改行が含まれると
# ずれ、null に tostring を掛けると文字列 "null" になる（4 つとも実測）。
# 大きい方の最適化は呼び出し側の安価な prefilter で取れているので、ここは正しさを取る。
tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
sid=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || sid=""
session=$(hook_session_id "$sid")

emit() { # emit <event> <skill> <path>
  # ts と mkdir は emit する回だけ。大半の呼び出しは何も書かずに終わる。
  local ts dir sandbox="no"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # cwd が sandbox 配下か。`/tmp` は macOS では `/private/tmp` への symlink で、runner.py が
  # base を resolve するため実ログに現れるのは後者だが、Linux や resolve を通らない経路では
  # 前者で来る。先頭の `/private` を 1 回剥がして 1 組の pattern で見る（両方の綴りを並べると
  # base や境界を変えるたびに 2 箇所を揃える必要が出る）。realpath を取らないのは、この判定が
  # 無人 hook の中にあるから — 余計な subprocess も、追従する symlink も増やさない。cwd を
  # 入れるのは CLI（セッションの working directory）で repo の中身ではないが、無人経路の
  # 入力は untrusted 側に倒して扱う。
  # 既知の取りこぼし: base 自体が symlink で別の場所を指す共有ホスト / CI（runner.py の
  # `_resolved_base` が扱う状況）では第三のパスになり tag が付かない。付かない側は修正前と
  # 同じ状態に落ちるだけで、本物の使用を sandbox と誤認するより安い。
  # 境界は `/` で切る — `…-sandbox-notes` を巻き込むと本物の使用が集計から消える。
  case "${cwd#/private}" in
    "$SKILL_COMPLY_SANDBOX_BASE" | "$SKILL_COMPLY_SANDBOX_BASE"/*) sandbox="yes" ;;
  esac
  # dirname の subprocess を避けるが、`/` を含まない相対パス（SKILL_USAGE_LOG の
  # ファイル名のみ指定）では ${LOG%/*} が LOG 自身を返す。そのまま mkdir すると
  # ログと同名のディレクトリを作り、以後の追記が黙って失敗する。
  # 追記先が symlink なら書かない。直前の commit が claims.jsonl へ O_NOFOLLOW を入れたのと
  # 同じ経路で、ここだけ未硬化だと、この path に symlink を 1 本置けるものが任意の
  # user-writable ファイルへ JSON 行を追記させられる（settings.json を壊せば hook 層が全部死ぬ）。
  [[ -L "$LOG" ]] && return
  dir="${LOG%/*}"
  [[ "$dir" == "$LOG" ]] && dir="."
  mkdir -p "$dir" 2>/dev/null || true
  # sandbox は sandbox 行にだけ現れる追加キー。`sandbox:false` を全行に足す形にすると
  # 2400 行超の既存ログと形が割れ、キー集合を見る読み手が壊れる。
  jq -cn --arg ts "$ts" --arg event "$1" --arg skill "$2" --arg path "$3" --arg project "$cwd" \
    --arg session "$session" --arg sandbox "$sandbox" \
    '{ts:$ts,event:$event,skill:$skill,path:$path,project:$project,session:$session}
     + (if $sandbox == "yes" then {sandbox:true} else {} end)' \
    >> "$LOG" 2>/dev/null || true
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

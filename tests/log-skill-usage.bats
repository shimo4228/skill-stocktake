#!/usr/bin/env bats
# Tests for hooks/log-skill-usage.sh — skill usage measurement hook.

setup() {
  export SKILL_USAGE_LOG="$BATS_TEST_TMPDIR/skill-usage.jsonl"
  HOOK="$BATS_TEST_DIRNAME/../hooks/log-skill-usage.sh"
}

@test "Skill invoke appends one invoke event with skill name and project" {
  run bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"my-skill\"},\"cwd\":\"/tmp/proj\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SKILL_USAGE_LOG" | tr -d ' ')" -eq 1 ]
  run jq -r '.event + " " + .skill + " " + .project' "$SKILL_USAGE_LOG"
  [ "$output" = "invoke my-skill /tmp/proj" ]
}

@test "Read of a directory-style skill file appends read event with derived skill name" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/foo/SKILL.md\"},\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run jq -r '.event + " " + .skill' "$SKILL_USAGE_LOG"
  [ "$output" = "read foo" ]
}

@test "Read of a single-file skill derives name from basename" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/solo-skill.md\"},\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run jq -r '.skill' "$SKILL_USAGE_LOG"
  [ "$output" = "solo-skill" ]
}

@test "Read of a project-level skill file is also logged" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/myproj/.claude/skills/bar/SKILL.md\"},\"cwd\":\"/tmp/myproj\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run jq -r '.skill + " " + .path' "$SKILL_USAGE_LOG"
  [ "$output" = "bar /tmp/myproj/.claude/skills/bar/SKILL.md" ]
}

@test "Read of a non-skill file appends nothing and exits 0" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/some/other.md\"},\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

@test "unrelated tool appends nothing and exits 0" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

@test "malformed stdin exits 0 without writing (hook must never break the session)" {
  run bash -c "echo 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

@test "every emitted line is valid JSON with the full schema" {
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/b/SKILL.md\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  run bash -c "jq -e 'has(\"ts\") and has(\"event\") and has(\"skill\") and has(\"path\") and has(\"project\") and has(\"session\")' '$SKILL_USAGE_LOG' | sort -u"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# session は simplify-order-notice.sh が順序判定に使う。has() の部分集合検査だけでは
# 「フィールドは在るが常に空」でも通ってしまうので、値の由来を別に pin する。

@test "a log override with no directory component still writes" {
  # 既存テストは全部絶対パスを渡すので、この経路は誰も踏んでいなかった。
  # dirname を ${LOG%/*} に置き換えると、`/` の無い指定でログと同名のディレクトリを
  # 作って以後の追記が黙って失敗する（2026-08-15 codex-review 指摘）。
  cd "$BATS_TEST_TMPDIR" || return 1
  SKILL_USAGE_LOG="usage.jsonl" \
    bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  [ -f "$BATS_TEST_TMPDIR/usage.jsonl" ]
  run jq -r '.skill' "$BATS_TEST_TMPDIR/usage.jsonl"
  [ "$output" = "a" ]
}

@test "a symlinked log is not followed" {
  # 直前の commit が claims.jsonl へ O_NOFOLLOW を入れたのと同じ経路。この path に
  # symlink を 1 本置けるものが、任意の user-writable ファイルへ JSON 行を追記できる
  # （settings.json に 1 行足せば JSON parse が壊れて hook 層が丸ごと落ちる）。
  local victim="$BATS_TEST_TMPDIR/victim.json"
  printf '{"keep":"me"}\n' > "$victim"
  ln -sf "$victim" "$SKILL_USAGE_LOG"
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  run cat "$victim"
  [ "$output" = '{"keep":"me"}' ]
}

@test "session comes from the stdin payload" {
  bash -c "echo '{\"tool_name\":\"Skill\",\"session_id\":\"sess-from-stdin\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  run jq -r '.session' "$SKILL_USAGE_LOG"
  [ "$output" = "sess-from-stdin" ]
}

@test "the env var is only a fallback and never overrides the payload" {
  # 逆順にすると、前セッションから持ち越した env が今の payload を上書きし、
  # 順序判定が古い simplify を「今走った」と読む (静かな偽陰性)。
  CLAUDE_CODE_SESSION_ID="sess-from-env" \
    bash -c "echo '{\"tool_name\":\"Skill\",\"session_id\":\"sess-from-stdin\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  run jq -r '.session' "$SKILL_USAGE_LOG"
  [ "$output" = "sess-from-stdin" ]
}

@test "the env var fills in when the payload has no session_id" {
  CLAUDE_CODE_SESSION_ID="sess-from-env" \
    bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/p\"}' | bash '$HOOK'"
  run jq -r '.session' "$SKILL_USAGE_LOG"
  [ "$output" = "sess-from-env" ]
}

# --- sandbox tagging (2026-08-17 追加) ---------------------------------------
# skill-comply の子セッションは sandbox を cwd にして走るので、その skill 使用が
# 計測ログに本物の使用として混ざる。S2 の実測では同じ比が sandbox 込み 0.750 /
# 除外 0.857 に割れた（.notes/TASKS.md の T-SIMPLIFY-NOTICE-EFFICACY 行）。
# 行は落とさず tag だけ足す — 落とすと既存の集計の分母が黙って変わる。

@test "a sandbox cwd (resolved /private/tmp form) is tagged sandbox: true" {
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/private/tmp/skill-comply-sandbox/run-58845/feat-add-neutral\"}' | bash '$HOOK'"
  run jq -r '.sandbox' "$SKILL_USAGE_LOG"
  [ "$output" = "true" ]
}

@test "a sandbox cwd (unresolved /tmp form) is tagged too" {
  # macOS では runner.py が base を resolve するので実際に現れるのは /private/tmp だが、
  # /tmp は symlink であって別の場所ではない。片方だけ見る判定は Linux と macOS で
  # 挙動が割れる。
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/tmp/skill-comply-sandbox/run-1/x\"}' | bash '$HOOK'"
  run jq -r '.sandbox' "$SKILL_USAGE_LOG"
  [ "$output" = "true" ]
}

@test "a sandbox path with no run-<pid> segment is tagged" {
  # 判定を `run-*/` へ絞らせないための guard。実ログには 27328a5 以前の `<base>/<id>` 行が
  # 残っており、レイアウトの世代で tag の有無が割れると読み手が窓ごとに違う母集団を見る。
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/private/tmp/skill-comply-sandbox/weekly-gate-neutral\"}' | bash '$HOOK'"
  run jq -r '.sandbox' "$SKILL_USAGE_LOG"
  [ "$output" = "true" ]
}

@test "a read event from a sandbox cwd is tagged as well" {
  bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/foo/SKILL.md\"},\"cwd\":\"/private/tmp/skill-comply-sandbox/run-1/x\"}' | bash '$HOOK'"
  run jq -r '.event + " " + (.sandbox|tostring)' "$SKILL_USAGE_LOG"
  [ "$output" = "read true" ]
}

# NOTE: テスト名は ASCII のみ。bats はテスト名から shell 関数名を作るので、
# 非 ASCII を含む名前は関数名が壊れて「そのテストだけ静かに実行されない」
# (実測: Executed 26 instead of expected 27 と出るが、他は全部 ok のまま)。
@test "an ordinary cwd yields the exact same 6 keys as before" {
  # 「sandbox: false を足す」ではない。既存の読み手（と 2400 行超の既存ログ）が
  # 見ている形をそのまま残し、tag は sandbox 行にだけ現れる追加キーにする。
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"$HOME/.claude\"}' | bash '$HOOK'"
  run jq -r 'keys_unsorted | join(",")' "$SKILL_USAGE_LOG"
  [ "$output" = "ts,event,skill,path,project,session" ]
}

@test "a lookalike path next to the sandbox base is not tagged" {
  # prefix 判定が境界を見ていないと、`…-sandbox-notes` のような隣接パスまで
  # sandbox 扱いになり、本物の使用が集計から消える（偽陽性は偽陰性より高くつく）。
  bash -c "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"a\"},\"cwd\":\"/tmp/skill-comply-sandbox-notes/x\"}' | bash '$HOOK'"
  run jq -r 'has("sandbox")' "$SKILL_USAGE_LOG"
  [ "$output" = "false" ]
}

@test "the hook's sandbox base agrees with runner.py's SANDBOX_BASE" {
  # 上の挙動テストは path を直書きするので、runner.py 側だけが動いた乖離
  # （tag が黙って付かなくなる）は全部 green のまま通る。そこだけをここで固定する。
  local runner="$BATS_TEST_DIRNAME/../skills/skill-comply/scripts/runner.py"
  local hook_base py_base
  hook_base=$(sed -n 's/^SKILL_COMPLY_SANDBOX_BASE="\(.*\)"$/\1/p' "$BATS_TEST_DIRNAME/../hooks/log-skill-usage.sh")
  py_base=$(sed -n 's/^SANDBOX_BASE = Path("\(.*\)")$/\1/p' "$runner")
  [ -n "$hook_base" ]
  [ "$hook_base" = "$py_base" ]
}

@test "shell metacharacters in a sandbox cwd are logged verbatim, never executed" {
  # この hook は無人で走る（rules/common/security.md）。cwd を入れるのは CLI だが、
  # 新しい分岐が injection 面を増やしていないことを値の往復で固定する。
  local marker="$BATS_TEST_TMPDIR/pwned"
  local evil='/private/tmp/skill-comply-sandbox/run-1/$(touch '"$marker"');`touch '"$marker"'`'
  jq -cn --arg cwd "$evil" '{tool_name:"Skill",tool_input:{skill:"a"},cwd:$cwd}' | bash "$HOOK"
  [ ! -e "$marker" ]
  run jq -r '.project + " " + (.sandbox|tostring)' "$SKILL_USAGE_LOG"
  [ "$output" = "$evil true" ]
}

# --- slash events (UserPromptSubmit) ---

setup_fake_skills() {
  export SKILL_USAGE_SKILLS_DIR="$BATS_TEST_TMPDIR/skills"
  mkdir -p "$SKILL_USAGE_SKILLS_DIR/my-skill"
  touch "$SKILL_USAGE_SKILLS_DIR/my-skill/SKILL.md"
  touch "$SKILL_USAGE_SKILLS_DIR/solo.md"
}

@test "user-typed /skill with args appends one slash event" {
  setup_fake_skills
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"/my-skill full-scan now\",\"cwd\":\"/tmp/proj\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SKILL_USAGE_LOG" | tr -d ' ')" -eq 1 ]
  run jq -r '.event + " " + .skill + " " + .project' "$SKILL_USAGE_LOG"
  [ "$output" = "slash my-skill /tmp/proj" ]
}

@test "slash resolves single-file skills too" {
  setup_fake_skills
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"/solo\",\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run jq -r '.skill + " " + .path' "$SKILL_USAGE_LOG"
  [ "$output" = "solo $SKILL_USAGE_SKILLS_DIR/solo.md" ]
}

@test "slash resolves project-level skills from cwd" {
  setup_fake_skills
  mkdir -p "$BATS_TEST_TMPDIR/proj/.claude/skills/proj-skill"
  touch "$BATS_TEST_TMPDIR/proj/.claude/skills/proj-skill/SKILL.md"
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"/proj-skill\",\"cwd\":\"$BATS_TEST_TMPDIR/proj\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run jq -r '.event + " " + .skill' "$SKILL_USAGE_LOG"
  [ "$output" = "slash proj-skill" ]
}

@test "built-in command slash (unresolvable name) appends nothing" {
  setup_fake_skills
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"/model opus\",\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

@test "plugin-namespaced slash (name with colon) appends nothing" {
  setup_fake_skills
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"/hookify:list\",\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

@test "non-slash prompt appends nothing" {
  setup_fake_skills
  run bash -c "echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"please run my-skill\",\"cwd\":\"/tmp\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$SKILL_USAGE_LOG" ]
}

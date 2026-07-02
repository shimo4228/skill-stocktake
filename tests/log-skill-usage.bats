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
  run bash -c "jq -e 'has(\"ts\") and has(\"event\") and has(\"skill\") and has(\"path\") and has(\"project\")' '$SKILL_USAGE_LOG' | sort -u"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
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

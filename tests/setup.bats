#!/usr/bin/env bats
load test_helper
setup() { setup_env; export HOME="$TD/home"; mkdir -p "$HOME"; SKILL="$HOME/.claude/skills/simlane"; }

@test "setup: links the skill from a git clone; a second run reports already linked" {
  run "$SIMLANE" setup
  [ "$status" -eq 0 ]; [ "$(readlink "$SKILL")" = "$SIMLANE_ROOT/skills/simlane" ]; assert_contains "$output" "skill linked"
  run "$SIMLANE" setup
  [ "$status" -eq 0 ]; assert_contains "$output" "already linked"
}

@test "setup: under a Homebrew prefix the skill points at opt/, not the versioned Cellar path" {
  make_brew_prefix "$TD/brew"
  run "$TD/brew/bin/simlane" setup
  [ "$status" -eq 0 ]
  [ "$(readlink "$SKILL")" = "$TD/brew/opt/simlane/libexec/skills/simlane" ]
  assert_not_contains "$(readlink "$SKILL")" "Cellar"
}

@test "setup: replaces a symlink that points elsewhere and names the old target" {
  mkdir -p "$HOME/.claude/skills" "$TD/old"; ln -s "$TD/old" "$SKILL"
  run "$SIMLANE" setup
  [ "$status" -eq 0 ]; [ "$(readlink "$SKILL")" = "$SIMLANE_ROOT/skills/simlane" ]
  assert_contains "$output" "relinked"; assert_contains "$output" "$TD/old"
}

@test "setup: refuses to replace a real skill directory" {
  mkdir -p "$SKILL"
  run "$SIMLANE" setup
  [ "$status" -eq 1 ]; assert_contains "$output" "real directory"; [ -d "$SKILL" ]; assert_fails [ -L "$SKILL" ]
}

@test "setup: an unknown argument exits 1 and changes nothing" {
  run "$SIMLANE" setup --hook
  [ "$status" -eq 1 ]; assert_contains "$output" "unknown argument: --hook"
  assert_fails [ -e "$SKILL" ]
}

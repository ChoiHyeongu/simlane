#!/usr/bin/env bats
load test_helper
setup() { setup_env; export HOME="$TD/home"; mkdir -p "$HOME"; }

@test "install.sh: links ~/bin/simlane and the skill; idempotent" {
  run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/bin/simlane")" = "$SIMLANE_ROOT/bin/simlane" ]
  [ "$(readlink "$HOME/.claude/skills/simlane")" = "$SIMLANE_ROOT/skills/simlane" ]
  run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]; assert_contains "$output" "already linked"
}

@test "install.sh: fails when setup refuses a real skill directory" {
  mkdir -p "$HOME/.claude/skills/simlane"
  run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 1 ]; assert_contains "$output" "real directory"
}

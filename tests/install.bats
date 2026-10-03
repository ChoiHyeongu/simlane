#!/usr/bin/env bats
load test_helper
setup() { setup_env; }

@test "install.sh: links ~/bin/simlane and, when the skill directory exists, ~/.claude/skills/simlane" {
  HOME="$TD/home" run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TD/home/bin/simlane")" = "$SIMLANE_ROOT/bin/simlane" ]
  if [ -d "$SIMLANE_ROOT/skills/simlane" ]; then
    [ "$(readlink "$TD/home/.claude/skills/simlane")" = "$SIMLANE_ROOT/skills/simlane" ]
  fi
  HOME="$TD/home" run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
}

@test "install.sh: refuses to link into a real (non-symlink) skill directory" {
  mkdir -p "$TD/home/.claude/skills/simlane"
  HOME="$TD/home" run "$SIMLANE_ROOT/scripts/install.sh"
  [ "$status" -eq 1 ]; assert_contains "$output" "real directory"
}

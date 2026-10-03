#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; export HOME="$TD/home"; mkdir -p "$HOME"; export CLAUDE_SETTINGS="$TD/settings.json"
  BIN="$SIMLANE_ROOT/bin/simlane"
  CMD="[ -x \"$BIN\" ] && \"$BIN\" claude-hook || true"
}
count_cmd() {   # EVENT COMMAND → number of hook entries with exactly that command
  jq --arg ev "$1" --arg c "$2" '[.hooks[$ev][]? | .hooks[]? | select(.command == $c)] | length' "$CLAUDE_SETTINGS"
}

@test "setup --hooks: creates the settings file and registers all three events with an absolute path" {
  run "$SIMLANE" setup --hooks; [ "$status" -eq 0 ]
  for ev in SessionStart CwdChanged FileChanged; do
    [ "$(count_cmd "$ev" "$CMD")" = "1" ]
    [ "$(jq -r --arg ev "$ev" '.hooks[$ev][0] | has("matcher")' "$CLAUDE_SETTINGS")" = "false" ]
  done
  [ -L "$HOME/.claude/skills/simlane" ]
}

@test "setup --hooks: keeps existing settings, backs up, and is idempotent" {
  echo '{"model":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$CLAUDE_SETTINGS"
  run "$SIMLANE" setup --hooks; [ "$status" -eq 0 ]
  [ "$(jq '.hooks.SessionStart | length' "$CLAUDE_SETTINGS")" = "2" ]; [ "$(jq -r .model "$CLAUDE_SETTINGS")" = "x" ]
  ls "$TD"/settings.json.bak.* >/dev/null
  run "$SIMLANE" setup --hooks; [ "$status" -eq 0 ]; assert_contains "$output" "hooks already registered"
  [ "$(jq '.hooks.SessionStart | length' "$CLAUDE_SETTINGS")" = "2" ]
}

@test "setup --hooks: replaces the old \$HOME/bin/simlane entry but keeps other tools' claude-hook entries" {
  old='[ -x "$HOME/bin/simlane" ] && "$HOME/bin/simlane" claude-hook || true'
  other='[ -x "$HOME/bin/othertool" ] && "$HOME/bin/othertool" claude-hook || true'
  jq -n --arg o "$old" --arg t "$other" \
    '{hooks:{SessionStart:[{hooks:[{type:"command",command:$o}]},{hooks:[{type:"command",command:$t}]}]}}' > "$CLAUDE_SETTINGS"
  run "$SIMLANE" setup --hooks; [ "$status" -eq 0 ]; assert_contains "$output" "removed 1 stale simlane hook entry"
  [ "$(count_cmd SessionStart "$old")" = "0" ]
  [ "$(count_cmd SessionStart "$other")" = "1" ]
  [ "$(count_cmd SessionStart "$CMD")" = "1" ]
}

@test "setup --hooks: entries without a command field are kept and do not break the merge" {
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"prompt","prompt":"hello"}]}]}}' > "$CLAUDE_SETTINGS"
  run "$SIMLANE" setup --hooks; [ "$status" -eq 0 ]
  [ "$(jq '[.hooks.SessionStart[] | .hooks[] | select(.type == "prompt")] | length' "$CLAUDE_SETTINGS")" = "1" ]
  [ "$(count_cmd SessionStart "$CMD")" = "1" ]
}

@test "setup --hooks: under a Homebrew prefix the hook calls the opt/ path" {
  make_brew_prefix "$TD/brew"
  run "$TD/brew/bin/simlane" setup --hooks; [ "$status" -eq 0 ]
  ob="$TD/brew/opt/simlane/libexec/bin/simlane"
  [ "$(count_cmd SessionStart "[ -x \"$ob\" ] && \"$ob\" claude-hook || true")" = "1" ]
  assert_not_contains "$(cat "$CLAUDE_SETTINGS")" "Cellar"
}

@test "setup --hooks: invalid JSON exits 1 and leaves the file untouched" {
  echo '{bad' > "$CLAUDE_SETTINGS"
  run "$SIMLANE" setup --hooks; [ "$status" -eq 1 ]; [ "$(cat "$CLAUDE_SETTINGS")" = "{bad" ]
}

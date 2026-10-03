#!/usr/bin/env bats
load test_helper
setup() { setup_env; export CLAUDE_SETTINGS="$TD/settings.json"; S="$SIMLANE_ROOT/scripts/install-claude-hooks.sh"; }
CMD='[ -x "$HOME/bin/simlane" ] && "$HOME/bin/simlane" claude-hook || true'

@test "creates the file when missing and registers all three events" {
  run "$S"; [ "$status" -eq 0 ]
  for ev in SessionStart CwdChanged FileChanged; do
    [ "$(jq -r --arg ev "$ev" '.hooks[$ev][0].hooks[0].command' "$CLAUDE_SETTINGS")" = "$CMD" ]
    [ "$(jq -r --arg ev "$ev" '.hooks[$ev][0] | has("matcher")' "$CLAUDE_SETTINGS")" = "false" ]
  done
}

@test "keeps existing hooks; a second run reports 'already registered' without duplicating" {
  echo '{"model":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$CLAUDE_SETTINGS"
  run "$S"; [ "$status" -eq 0 ]
  [ "$(jq '.hooks.SessionStart | length' "$CLAUDE_SETTINGS")" = "2" ]
  [ "$(jq -r '.model' "$CLAUDE_SETTINGS")" = "x" ]
  ls "$TD"/settings.json.bak.* >/dev/null
  run "$S"; [ "$status" -eq 0 ]; assert_contains "$output" "already registered"
  [ "$(jq '.hooks.SessionStart | length' "$CLAUDE_SETTINGS")" = "2" ]
}

@test "registers only the events that are missing" {
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":%s}]}]}}\n' "$(jq -Rn --arg c "$CMD" '$c')" > "$CLAUDE_SETTINGS"
  run "$S"; [ "$status" -eq 0 ]
  for ev in SessionStart CwdChanged FileChanged; do
    [ "$(jq --arg ev "$ev" --arg c "$CMD" '[.hooks[$ev][] | .hooks[] | select(.command == $c)] | length' "$CLAUDE_SETTINGS")" = "1" ]
  done
}

@test "replaces stale claude-hook entries that point at an old binary" {
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"[ -x \"$HOME/bin/oldtool\" ] && \"$HOME/bin/oldtool\" claude-hook || true"}]}],"CwdChanged":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}' > "$CLAUDE_SETTINGS"
  run "$S"; [ "$status" -eq 0 ]; assert_contains "$output" "removed"
  [ "$(jq '[.hooks[][] | .hooks[] | select(.command | test("oldtool"))] | length' "$CLAUDE_SETTINGS")" = "0" ]
  [ "$(jq '[.hooks.CwdChanged[] | .hooks[] | select(.command == "echo keep")] | length' "$CLAUDE_SETTINGS")" = "1" ]
  for ev in SessionStart CwdChanged FileChanged; do
    [ "$(jq --arg ev "$ev" --arg c "$CMD" '[.hooks[$ev][] | .hooks[] | select(.command == $c)] | length' "$CLAUDE_SETTINGS")" = "1" ]
  done
}

@test "invalid JSON exits 1 and leaves the file untouched" {
  echo '{bad' > "$CLAUDE_SETTINGS"
  run "$S"; [ "$status" -eq 1 ]; [ "$(cat "$CLAUDE_SETTINGS")" = "{bad" ]
}

# Release Pipeline and Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship simlane through a Homebrew tap with tag-driven CI releases, a `VERSION` file, `simlane --version` and a
`simlane setup` command that survives `brew upgrade`.

**Architecture:** Every decision lives in small bash scripts covered by bats (`changelog-section.sh`,
`check-release.sh`, `update-formula.sh`, `release.sh`, `simlane setup`); the two GitHub Actions workflows only call
them. Paths that outside files point at (the skill link, the hook command) go through `simlane::stable_home`, which maps
a Homebrew `Cellar/<version>` path to the version-independent `opt` path.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), jq, awk, git, bats-core, shellcheck, actionlint, GitHub Actions
(`macos-latest`), Homebrew formula (Ruby DSL).

**Spec:** `docs/superpowers/specs/2026-10-03-release-pipeline-design.md`

## Global Constraints

- bash 3.2 compatible: no `declare -A`, `mapfile`, `${var,,}`, `local -n`; empty arrays as `${arr[@]+"${arr[@]}"}`.
- `bin/simlane` and `scripts/*.sh` run with `set -euo pipefail`; `lib/*.sh` are sourced and must not set it.
- Never put a fallible command on the left of `&&` as the *last* line of a function (its failure becomes the return
  code) and never rely on `cmd1 && cmd2` to stop on `cmd2` failure — use `if` for anything whose failure matters.
- Tests: assertions only through `[ … ]` (a command) and the helpers `assert_contains`, `assert_not_contains`,
  `assert_endswith`, `assert_fails` from `tests/test_helper.bash`. Never `[[ ]]` or `! cmd` in a test.
- Functions are namespaced `simlane::`, subcommands `cmd_*`, one subcommand per file in `lib/cmd/`.
- Messages, comments, test names in English.
- Never run `simlane up/down/gc` against the real machine; `help`, `env`, `status`, `--version` are fine.
- Exact names: code repo `ChoiHyeongu/simlane`; tap repo `ChoiHyeongu/homebrew-tap`; formula
  `Formula/simlane.rb`; install command `brew install choihyeongu/tap/simlane`; Actions secret `TAP_GITHUB_TOKEN`;
  tag format `vX.Y.Z`; tarball URL `https://github.com/ChoiHyeongu/simlane/archive/refs/tags/vX.Y.Z.tar.gz`.
- SemVer; while 0.x a breaking change (exit codes, `.simlane.json` schema, `SIMLANE_*` variables, CLI flags) bumps minor.
- Commits: Conventional Commits in English, ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  (CLAUDE.md). Don't push unless the maintainer asks.
- Work happens on branch `feature/release-pipeline`.

## Review Focus

1. A Homebrew-layout install (`<prefix>/bin/simlane` → `Cellar/simlane/<v>/libexec/bin/simlane`) running `setup` must
   link the skill and write the hook against `<prefix>/opt/simlane/libexec`, never the versioned Cellar path —
   pinned in Task 3 (skill) and Task 4 (hooks) with a fake prefix.
2. `~/.claude/settings.json` hook entries without a `command` field (other hook types) must not make `setup --hooks`
   crash or drop them — pinned in Task 4.
3. A mistyped flag (`simlane setup --hook`) must exit 1 without touching anything — pinned in Task 3.
4. A `## Unreleased` section that contains only blank lines counts as empty and blocks a release — pinned in Task 5
   and Task 7.
5. A `VERSION` file with trailing whitespace/newlines must still print and compare as `X.Y.Z` — pinned in Task 1 and
   Task 5.

---

### Task 1: `VERSION` file and `simlane --version`

**Files:**
- Create: `VERSION`
- Create: `lib/cmd/version.sh`
- Modify: `bin/simlane` (usage text, `main` dispatch)
- Modify: `CHANGELOG.md` (add `## Unreleased`)
- Test: `tests/version.bats`

**Interfaces:**
- Produces: `cmd_version` — prints the content of `$SIMLANE_HOME/VERSION` with all whitespace removed plus one newline;
  exit 1 with `VERSION file not found: <path>` when missing. CLI: `simlane --version`, `simlane -V`, `simlane version`.
- Produces: `VERSION` containing `0.1.0` (the current release; `release.sh` bumps it).

- [ ] **Step 1: Write the failing test**

`tests/version.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() { setup_env; }

copy_tree() {   # DIR [VERSION_CONTENT] → a copy of bin/ and lib/ with an optional VERSION file
  mkdir -p "$1"
  cp -R "$SIMLANE_ROOT/bin" "$SIMLANE_ROOT/lib" "$1/"
  if [ $# -gt 1 ]; then printf '%b' "$2" > "$1/VERSION"; fi
}

@test "VERSION is a plain X.Y.Z" {
  grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$SIMLANE_ROOT/VERSION"
}

@test "--version, -V and version print the VERSION file" {
  want=$(tr -d '[:space:]' < "$SIMLANE_ROOT/VERSION")
  run "$SIMLANE" --version; [ "$status" -eq 0 ]; [ "$output" = "$want" ]
  run "$SIMLANE" -V;        [ "$status" -eq 0 ]; [ "$output" = "$want" ]
  run "$SIMLANE" version;   [ "$status" -eq 0 ]; [ "$output" = "$want" ]
}

@test "--version strips surrounding whitespace and blank lines" {
  copy_tree "$TD/t" ' 0.9.1 \n\n'
  run "$TD/t/bin/simlane" --version
  [ "$status" -eq 0 ]; [ "$output" = "0.9.1" ]
}

@test "--version fails clearly when VERSION is missing" {
  copy_tree "$TD/t"
  run "$TD/t/bin/simlane" --version
  [ "$status" -eq 1 ]; assert_contains "$output" "VERSION file not found"
}

@test "help lists the version command" {
  run "$SIMLANE" help
  assert_contains "$output" "--version"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/version.bats`
Expected: FAIL — `VERSION is a plain X.Y.Z` (no file) and the CLI tests (`simlane --version` prints usage, exit 1).

- [ ] **Step 3: Implement**

`VERSION`:

```
0.1.0
```

`lib/cmd/version.sh`:

```bash
#!/usr/bin/env bash
# simlane version — print the installed version (the VERSION file at the install root)

cmd_version() {
  local f="$SIMLANE_HOME/VERSION"
  [ -f "$f" ] || simlane::die 1 "VERSION file not found: $f"
  tr -d '[:space:]' < "$f"
  printf '\n'
}
```

In `bin/simlane`, add to the `usage` heredoc after the `claude-hook` line:

```
  setup [--hooks]    link the Claude Code skill; --hooks also registers the session hooks
  version, --version print the installed version
```

and add to the `case` in `main` before `help|-h|--help)`:

```bash
    version|--version|-V) cmd_version "$@" ;;
```

(`setup` is listed now and implemented in Task 3; the usage text is written once.)

In `CHANGELOG.md`, insert after the `# Changelog` heading and its blank line:

```markdown
## Unreleased

- `simlane --version` and a `VERSION` file.

```

- [ ] **Step 4: Run tests**

Run: `bats tests/version.bats && bats tests/`
Expected: PASS, whole suite green.

- [ ] **Step 5: Commit**

```bash
git add VERSION lib/cmd/version.sh bin/simlane CHANGELOG.md tests/version.bats
git commit -m "feat: add VERSION file and simlane --version

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `simlane::stable_home`

**Files:**
- Modify: `lib/common.sh` (append function)
- Test: `tests/common.bats` (append tests)

**Interfaces:**
- Produces: `simlane::stable_home [PATH]` — PATH defaults to `$SIMLANE_HOME`. If PATH matches
  `*/Cellar/simlane/*/libexec`, prints `<prefix>/opt/simlane/libexec` where `<prefix>` is everything before
  `/Cellar/simlane/`; otherwise prints PATH unchanged. Never calls `brew`.

- [ ] **Step 1: Write the failing tests** — append to `tests/common.bats`:

```bash
@test "stable_home: a Homebrew Cellar path maps to the version-independent opt path" {
  source_libs
  [ "$(simlane::stable_home /opt/homebrew/Cellar/simlane/0.2.0/libexec)" = "/opt/homebrew/opt/simlane/libexec" ]
  [ "$(simlane::stable_home /usr/local/Cellar/simlane/1.10.3_1/libexec)" = "/usr/local/opt/simlane/libexec" ]
}

@test "stable_home: a git clone path is returned unchanged, and SIMLANE_HOME is the default" {
  source_libs
  [ "$(simlane::stable_home /Users/x/.local/share/simlane)" = "/Users/x/.local/share/simlane" ]
  [ "$(simlane::stable_home /tmp/Cellar/other/1.0/libexec)" = "/tmp/Cellar/other/1.0/libexec" ]
  [ "$(SIMLANE_HOME=/a/Cellar/simlane/0.3.0/libexec simlane::stable_home)" = "/a/opt/simlane/libexec" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/common.bats`
Expected: the two new tests FAIL with `simlane::stable_home: command not found`.

- [ ] **Step 3: Implement** — append to `lib/common.sh`:

```bash
simlane::stable_home() {   # [PATH] → the install root that outside files (skill link, hook command) may point at
  # Homebrew resolves bin/simlane to <prefix>/Cellar/simlane/<version>/libexec, which `brew cleanup` deletes after an
  # upgrade; <prefix>/opt/simlane always points at the current version. No `brew` call: hooks run on every event.
  local h=${1:-$SIMLANE_HOME}
  case "$h" in
    */Cellar/simlane/*/libexec) printf '%s/opt/simlane/libexec\n' "${h%%/Cellar/simlane/*}" ;;
    *) printf '%s\n' "$h" ;;
  esac
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/common.bats && bats tests/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/common.bats
git commit -m "feat: add simlane::stable_home for Homebrew-safe install paths

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `simlane setup` (skill link) and `install.sh` on top of it

**Files:**
- Create: `lib/cmd/setup.sh`
- Modify: `bin/simlane` (`main` dispatch)
- Modify: `scripts/install.sh`
- Modify: `tests/test_helper.bash` (add `make_brew_prefix`)
- Create: `tests/setup.bats`
- Modify: `tests/install.bats`

**Interfaces:**
- Consumes: `simlane::stable_home` (Task 2).
- Produces: `cmd_setup [--hooks]` — unknown argument → exit 1, nothing changed. Calls `simlane::setup_skill <home>`,
  and with `--hooks` calls `simlane::setup_hooks <home>/bin/simlane` (defined in Task 4; until then `--hooks` exits 1
  with `--hooks is not available yet` — Task 4 replaces that branch).
- Produces: `simlane::setup_skill STABLE_HOME` — links `$HOME/.claude/skills/simlane` → `STABLE_HOME/skills/simlane`.
  Messages (stderr, via `simlane::log`): `skill linked: …`, `skill already linked: …`, `skill relinked: … (was …)`;
  real directory → exit 1 with `… is a real directory, not a symlink …`.
- Produces (tests): `make_brew_prefix DIR` in `tests/test_helper.bash` — builds a fake Homebrew prefix with
  `DIR/Cellar/simlane/0.2.0/libexec/{bin,lib,skills,VERSION}`, `DIR/Cellar/simlane/0.2.0/bin/simlane` →
  `../libexec/bin/simlane`, `DIR/opt/simlane` → `../Cellar/simlane/0.2.0`, `DIR/bin/simlane` →
  `../Cellar/simlane/0.2.0/bin/simlane`.
- `scripts/install.sh [--hooks]` — links `~/bin/simlane`, then runs `bin/simlane setup "$@"`.

- [ ] **Step 1: Add the test helper** — append to `tests/test_helper.bash` (before the assert helpers):

```bash
make_brew_prefix() {   # DIR → a fake Homebrew prefix with simlane 0.2.0 installed the way the formula installs it
  local p=$1 c="$1/Cellar/simlane/0.2.0"
  mkdir -p "$c/libexec" "$c/bin" "$p/opt" "$p/bin"
  cp -R "$SIMLANE_ROOT/bin" "$SIMLANE_ROOT/lib" "$SIMLANE_ROOT/skills" "$SIMLANE_ROOT/VERSION" "$c/libexec/"
  ln -s ../libexec/bin/simlane "$c/bin/simlane"
  ln -s ../Cellar/simlane/0.2.0 "$p/opt/simlane"
  ln -s ../Cellar/simlane/0.2.0/bin/simlane "$p/bin/simlane"
}
```

- [ ] **Step 2: Write the failing tests** — `tests/setup.bats`:

```bash
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
```

Replace `tests/install.bats` with:

```bash
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
```

- [ ] **Step 3: Run to verify failure**

Run: `bats tests/setup.bats tests/install.bats`
Expected: FAIL — `simlane setup` prints usage and exits 1.

- [ ] **Step 4: Implement**

`lib/cmd/setup.sh`:

```bash
#!/usr/bin/env bash
# simlane setup — link the Claude Code skill; --hooks also registers `simlane claude-hook` in ~/.claude/settings.json.
# Paths come from simlane::stable_home so they survive `brew upgrade`.

cmd_setup() {
  local hooks=0 arg home
  for arg in "$@"; do
    case "$arg" in
      --hooks) hooks=1 ;;
      *) simlane::die 1 "unknown argument: $arg (usage: simlane setup [--hooks])" ;;
    esac
  done
  home=$(simlane::stable_home)
  simlane::setup_skill "$home"
  if [ "$hooks" -eq 1 ]; then
    simlane::die 1 "--hooks is not available yet"
  fi
}

simlane::setup_skill() {   # STABLE_HOME → link ~/.claude/skills/simlane to STABLE_HOME/skills/simlane
  local src="$1/skills/simlane" dst="$HOME/.claude/skills/simlane" old
  [ -d "$src" ] || simlane::die 1 "skill directory not found: $src"
  mkdir -p "$HOME/.claude/skills"
  if [ -L "$dst" ]; then
    old=$(readlink "$dst")
    if [ "$old" = "$src" ]; then
      simlane::log "skill already linked: $dst → $src"
      return 0
    fi
    ln -sfn "$src" "$dst"
    simlane::log "skill relinked: $dst → $src (was $old)"
    return 0
  fi
  if [ -e "$dst" ]; then
    simlane::die 1 "refusing to link: $dst is a real directory, not a symlink. Move it away and re-run."
  fi
  ln -s "$src" "$dst"
  simlane::log "skill linked: $dst → $src"
}
```

In `bin/simlane` `main`, add before the `version|…` line:

```bash
    setup)       cmd_setup "$@" ;;
```

Replace `scripts/install.sh` with:

```bash
#!/usr/bin/env bash
# Contributor install from a git clone: symlink ~/bin/simlane, then `simlane setup` (skill; pass --hooks for hooks).
# Users install with Homebrew instead (README). Idempotent.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
mkdir -p "$HOME/bin"
ln -sfn "$HERE/bin/simlane" "$HOME/bin/simlane"
echo "installed: $HOME/bin/simlane → $HERE/bin/simlane"
"$HERE/bin/simlane" setup "$@"
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "note: $HOME/bin is not on your PATH; add it in your shell rc" ;;
esac
```

- [ ] **Step 5: Run tests**

Run: `bats tests/setup.bats tests/install.bats && bats tests/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/cmd/setup.sh bin/simlane scripts/install.sh tests/test_helper.bash tests/setup.bats tests/install.bats
git commit -m "feat: add simlane setup to link the Claude Code skill

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `simlane setup --hooks` (replaces `install-claude-hooks.sh`)

**Files:**
- Modify: `lib/cmd/setup.sh`
- Delete: `scripts/install-claude-hooks.sh`, `tests/install_hooks.bats`
- Create: `tests/setup_hooks.bats`
- Modify: `CHANGELOG.md` (Unreleased lines)

**Interfaces:**
- Consumes: `cmd_setup`, `simlane::stable_home`, `make_brew_prefix` (Tasks 2–3).
- Produces: `simlane::setup_hooks BIN` — settings file `${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}`; hook command
  exactly `[ -x "BIN" ] && "BIN" claude-hook || true`; registers it on `SessionStart`, `CwdChanged`, `FileChanged`;
  removes other entries whose command matches the regex `simlane"? claude-hook`; keeps everything else (including
  entries without a `command`). Messages: `hooks already registered: <file>`,
  `removed N stale simlane hook entr(y|ies)`, `hooks registered: <file> (backup: <file>.bak.*)`. Invalid JSON → exit 1,
  file untouched.

- [ ] **Step 1: Write the failing tests** — `tests/setup_hooks.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/setup_hooks.bats`
Expected: FAIL — `--hooks is not available yet`.

- [ ] **Step 3: Implement**

In `lib/cmd/setup.sh`, replace the `if [ "$hooks" -eq 1 ]` block in `cmd_setup` with:

```bash
  if [ "$hooks" -eq 1 ]; then
    simlane::setup_hooks "$home/bin/simlane"
  fi
```

and append:

```bash
simlane::setup_hooks() {   # BIN → register `BIN claude-hook` for SessionStart, CwdChanged and FileChanged
  # Idempotent per event; replaces simlane entries pointing at another binary (e.g. the old ~/bin/simlane); keeps every
  # other hook, including other tools' claude-hook entries; backs the file up before writing.
  local f="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}" bin=$1 cmd re stale missing tmp
  cmd="[ -x \"$bin\" ] && \"$bin\" claude-hook || true"
  re='simlane"? claude-hook'
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || simlane::die 1 "settings.json is not valid JSON: $f"

  stale=$(jq --arg c "$cmd" --arg re "$re" \
    '[.hooks // {} | .[]? | .[]? | .hooks[]? | (.command // "") | select(. != $c and test($re))] | length' "$f")
  missing=$(jq --arg c "$cmd" \
    '[("SessionStart","CwdChanged","FileChanged") as $ev | select(([.hooks[$ev][]? | .hooks[]? | .command] | index($c)) == null)] | length' "$f")
  if [ "$stale" -eq 0 ] && [ "$missing" -eq 0 ]; then
    simlane::log "hooks already registered: $f"
    return 0
  fi

  cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  jq --arg c "$cmd" --arg re "$re" '
    def group: {hooks: [{type: "command", command: $c}]};
    def drop_stale: map(.hooks |= map(select(((.command // "") | test($re) | not) or .command == $c))) | map(select(.hooks | length > 0));
    def ensure: if ([.[]? | .hooks[]? | .command] | index($c)) == null then . + [group] else . end;
    .hooks = ((.hooks // {})
      | with_entries(.value |= (if type == "array" then drop_stale else . end))
      | .SessionStart = ((.SessionStart // []) | ensure)
      | .CwdChanged   = ((.CwdChanged   // []) | ensure)
      | .FileChanged  = ((.FileChanged  // []) | ensure))
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
  if [ "$stale" -gt 0 ]; then
    if [ "$stale" -eq 1 ]; then simlane::log "removed 1 stale simlane hook entry"
    else simlane::log "removed $stale stale simlane hook entries"; fi
  fi
  simlane::log "hooks registered: $f (backup: $f.bak.*)"
}
```

Delete the old script and its tests:

```bash
git rm -q scripts/install-claude-hooks.sh tests/install_hooks.bats
```

Add to `CHANGELOG.md` under `## Unreleased`:

```markdown
- `simlane setup [--hooks]` links the Claude Code skill and registers the hooks; replaces
  `scripts/install-claude-hooks.sh`. Paths survive `brew upgrade`.
- Hook registration no longer removes other tools' `claude-hook` entries.
```

- [ ] **Step 4: Run tests**

Run: `bats tests/setup_hooks.bats && bats tests/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cmd/setup.sh tests/setup_hooks.bats CHANGELOG.md
git commit -m "feat!: move hook registration into simlane setup --hooks

The hook command now uses the absolute, upgrade-safe install path instead of ~/bin/simlane,
and only replaces simlane's own stale entries.

BREAKING CHANGE: scripts/install-claude-hooks.sh is removed; run simlane setup --hooks.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `changelog-section.sh` and `check-release.sh`

**Files:**
- Create: `scripts/changelog-section.sh`, `scripts/check-release.sh`
- Test: `tests/release_checks.bats`

**Interfaces:**
- Produces: `scripts/changelog-section.sh NAME [CHANGELOG]` — NAME is `X.Y.Z` or `Unreleased`; prints the section body
  (lines after `## NAME …` up to the next `## `), leading/trailing blank lines trimmed. Exit 1 with
  `no '## NAME' section` or `'## NAME' section is empty`. CHANGELOG defaults to the repo's `CHANGELOG.md`.
- Produces: `scripts/check-release.sh vX.Y.Z [REPO_ROOT]` — exit 0 printing `check-release: vX.Y.Z ok` when the tag is
  `v` + SemVer, `VERSION` (whitespace stripped) equals X.Y.Z, the first non-`Unreleased` `## ` heading of
  `CHANGELOG.md` is X.Y.Z, and that section is non-empty; otherwise exit 1 with `check-release: <reason>`.

- [ ] **Step 1: Write the failing tests** — `tests/release_checks.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; CS="$SIMLANE_ROOT/scripts/changelog-section.sh"; CR="$SIMLANE_ROOT/scripts/check-release.sh"
  R="$TD/r"; mkdir -p "$R"
  printf '%s\n' '# Changelog' '' '## Unreleased' '' '- next thing' '' '## 0.2.0 — 2026-10-04' '' '- a' '- b' '' \
    '## 0.1.0 — 2026-10-03' '' '- first' > "$R/CHANGELOG.md"
  echo 0.2.0 > "$R/VERSION"
}

@test "changelog-section: prints one version's body without the heading or surrounding blank lines" {
  run "$CS" 0.2.0 "$R/CHANGELOG.md"
  [ "$status" -eq 0 ]; [ "$output" = "$(printf '%s\n%s' '- a' '- b')" ]
  run "$CS" 0.1.0 "$R/CHANGELOG.md"; [ "$output" = "- first" ]
  run "$CS" Unreleased "$R/CHANGELOG.md"; [ "$output" = "- next thing" ]
}

@test "changelog-section: a missing section exits 1" {
  run "$CS" 9.9.9 "$R/CHANGELOG.md"; [ "$status" -eq 1 ]; assert_contains "$output" "no '## 9.9.9' section"
}

@test "changelog-section: a section with only blank lines counts as empty" {
  printf '%s\n' '# Changelog' '' '## Unreleased' '' '   ' '' '## 0.1.0 — 2026-10-03' '' '- first' > "$R/CHANGELOG.md"
  run "$CS" Unreleased "$R/CHANGELOG.md"; [ "$status" -eq 1 ]; assert_contains "$output" "is empty"
}

@test "check-release: tag, VERSION and newest CHANGELOG section agree" {
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 0 ]; assert_contains "$output" "v0.2.0 ok"
}

@test "check-release: VERSION with surrounding whitespace still matches" {
  printf ' 0.2.0 \n\n' > "$R/VERSION"
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 0 ]
}

@test "check-release: rejects a malformed tag, a VERSION mismatch and a CHANGELOG mismatch" {
  run "$CR" 0.2.0 "$R";   [ "$status" -eq 1 ]; assert_contains "$output" "not a release tag"
  run "$CR" v0.2 "$R";    [ "$status" -eq 1 ]; assert_contains "$output" "not a release tag"
  echo 0.3.0 > "$R/VERSION"
  run "$CR" v0.3.0 "$R";  [ "$status" -eq 1 ]; assert_contains "$output" "newest CHANGELOG section is 0.2.0"
  run "$CR" v0.2.0 "$R";  [ "$status" -eq 1 ]; assert_contains "$output" "VERSION is 0.3.0"
}

@test "check-release: a missing VERSION file fails" {
  rm "$R/VERSION"
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 1 ]; assert_contains "$output" "VERSION file missing"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/release_checks.bats`
Expected: FAIL — scripts do not exist (exit 127).

- [ ] **Step 3: Implement**

`scripts/changelog-section.sh`:

```bash
#!/usr/bin/env bash
# Print one CHANGELOG section body: changelog-section.sh X.Y.Z|Unreleased [CHANGELOG]
# Heading lines look like "## 0.2.0 — 2026-10-04" or "## Unreleased". Exit 1 if the section is missing or empty.
set -euo pipefail
name=${1:?usage: changelog-section.sh X.Y.Z|Unreleased [CHANGELOG]}
f=${2:-$(cd "$(dirname "$0")/.." && pwd -P)/CHANGELOG.md}
rc=0
awk -v name="$name" '
  /^## / { if (found) exit; if ($2 == name) { found = 1; next } }
  found { lines[++n] = $0 }
  END {
    if (!found) exit 2
    s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
    e = n; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
    if (s > e) exit 3
    for (i = s; i <= e; i++) print lines[i]
  }
' "$f" || rc=$?
case $rc in
  0) ;;
  2) echo "changelog-section: no '## $name' section in $f" >&2; exit 1 ;;
  3) echo "changelog-section: '## $name' section is empty in $f" >&2; exit 1 ;;
  *) exit 1 ;;
esac
```

`scripts/check-release.sh`:

```bash
#!/usr/bin/env bash
# Assert a release tag matches VERSION and the newest CHANGELOG section: check-release.sh vX.Y.Z [REPO_ROOT]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
tag=${1:?usage: check-release.sh vX.Y.Z [REPO_ROOT]}
root=${2:-$(cd "$here/.." && pwd -P)}
fail() { echo "check-release: $*" >&2; exit 1; }

printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "not a release tag: $tag"
v=${tag#v}
[ -f "$root/VERSION" ] || fail "VERSION file missing in $root"
file_v=$(tr -d '[:space:]' < "$root/VERSION")
[ "$file_v" = "$v" ] || fail "tag $tag but VERSION is $file_v"
top=$(awk '/^## / && $2 != "Unreleased" { print $2; exit }' "$root/CHANGELOG.md")
[ "$top" = "$v" ] || fail "tag $tag but the newest CHANGELOG section is ${top:-missing}"
"$here/changelog-section.sh" "$v" "$root/CHANGELOG.md" >/dev/null || fail "CHANGELOG section for $v is missing or empty"
echo "check-release: $tag ok"
```

```bash
chmod +x scripts/changelog-section.sh scripts/check-release.sh
```

- [ ] **Step 4: Run tests**

Run: `bats tests/release_checks.bats && bats tests/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/changelog-section.sh scripts/check-release.sh tests/release_checks.bats
git commit -m "feat: add changelog-section and check-release scripts

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `update-formula.sh`

**Files:**
- Create: `scripts/update-formula.sh`
- Test: `tests/update_formula.bats`

**Interfaces:**
- Produces: `scripts/update-formula.sh FORMULA_RB X.Y.Z SHA256` — rewrites the single top-level (two-space indented)
  `url "…"` line to the Global Constraints tarball URL and the single `sha256 "…"` line; prints `updated` or
  `unchanged`; exit 1 on a bad version, a sha256 that is not 64 lowercase hex chars, or a formula without exactly one
  of each line. Keeps the file's permissions (writes through `cat >`).

- [ ] **Step 1: Write the failing tests** — `tests/update_formula.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; U="$SIMLANE_ROOT/scripts/update-formula.sh"; F="$TD/simlane.rb"
  SHA_A=$(printf 'a%.0s' $(seq 64)); SHA_B=$(printf 'b%.0s' $(seq 64))
  cat > "$F" <<RB
class Simlane < Formula
  desc "One iOS simulator + Metro lane per git worktree"
  homepage "https://github.com/ChoiHyeongu/simlane"
  url "https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$SHA_A"
  license "MIT"
end
RB
}

@test "update-formula: rewrites url and sha256, then reports unchanged on a repeat" {
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 0 ]; [ "$output" = "updated" ]
  grep -qx '  url "https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.2.0.tar.gz"' "$F"
  grep -qx "  sha256 \"$SHA_B\"" "$F"
  grep -qx '  license "MIT"' "$F"
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 0 ]; [ "$output" = "unchanged" ]
}

@test "update-formula: rejects a bad version or sha256 without touching the file" {
  before=$(cat "$F")
  run "$U" "$F" v0.2.0 "$SHA_B"; [ "$status" -eq 1 ]; assert_contains "$output" "bad version"
  run "$U" "$F" 0.2.0 abc;       [ "$status" -eq 1 ]; assert_contains "$output" "bad sha256"
  [ "$(cat "$F")" = "$before" ]
}

@test "update-formula: refuses a formula without exactly one url and one sha256 line" {
  printf '%s\n' 'class Simlane < Formula' '  sha256 "x"' 'end' > "$F"
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 1 ]; assert_contains "$output" "exactly one"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/update_formula.bats`
Expected: FAIL (exit 127).

- [ ] **Step 3: Implement** — `scripts/update-formula.sh`:

```bash
#!/usr/bin/env bash
# Point the Homebrew formula at a release: update-formula.sh FORMULA_RB X.Y.Z SHA256 → prints updated|unchanged
set -euo pipefail
f=${1:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
v=${2:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
sha=${3:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
fail() { echo "update-formula: $*" >&2; exit 1; }

printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "bad version: $v"
printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{64}$' || fail "bad sha256: $sha"
if [ "$(grep -c '^  url "' "$f")" -ne 1 ] || [ "$(grep -c '^  sha256 "' "$f")" -ne 1 ]; then
  fail "expected exactly one top-level url and one sha256 line in $f"
fi

url="https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v$v.tar.gz"
tmp=$(mktemp)
sed -e "s|^  url \".*\"\$|  url \"$url\"|" -e "s|^  sha256 \".*\"\$|  sha256 \"$sha\"|" "$f" > "$tmp"
if cmp -s "$tmp" "$f"; then
  rm -f "$tmp"; echo unchanged
else
  cat "$tmp" > "$f"; rm -f "$tmp"; echo updated
fi
```

```bash
chmod +x scripts/update-formula.sh
```

- [ ] **Step 4: Run tests**

Run: `bats tests/update_formula.bats && bats tests/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/update-formula.sh tests/update_formula.bats
git commit -m "feat: add update-formula script for the Homebrew tap

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: `scripts/release.sh`

**Files:**
- Create: `scripts/release.sh`
- Test: `tests/release.bats`

**Interfaces:**
- Consumes: `scripts/changelog-section.sh Unreleased CHANGELOG.md` (Task 5).
- Produces: `scripts/release.sh X.Y.Z`, run anywhere inside the repo. Order: preconditions → tests → CHANGELOG + VERSION
  → commit `chore(release): X.Y.Z` + annotated tag `vX.Y.Z` (`simlane X.Y.Z`) → prompt on stdin
  `push main and vX.Y.Z to origin? [y/N]` → `git push --atomic origin main vX.Y.Z`. Test command is
  `${SIMLANE_RELEASE_TEST_CMD:-bats tests/}` run through `bash -c`. All failures exit 1 with `release: <reason>`;
  a declined push exits 0 and prints `git tag -d vX.Y.Z && git reset --hard HEAD~1`.

- [ ] **Step 1: Write the failing tests** — `tests/release.bats`:

```bash
#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; S="$SIMLANE_ROOT/scripts/release.sh"; O="$TD/origin.git"; R="$TD/r"
  git init -q --bare "$O"
  git clone -q "$O" "$R" 2>/dev/null
  ( cd "$R" && git symbolic-ref HEAD refs/heads/main && git config user.email t@t.local && git config user.name t \
    && echo 0.1.0 > VERSION \
    && printf '%s\n' '# Changelog' '' '## Unreleased' '' '- feat: something' '' '## 0.1.0 — 2026-10-01' '' '- first' > CHANGELOG.md \
    && git add -A && git commit -qm init && git push -q origin main )
  TODAY=$(date +%Y-%m-%d)
}
rel() {   # ANSWER ARGS… → run release.sh inside $R with ANSWER on stdin and a stub test command
  local ans=$1; shift
  ( cd "$R" && printf '%s\n' "$ans" | SIMLANE_RELEASE_TEST_CMD="${TESTCMD:-true}" "$S" "$@" )
}
clean() { [ -z "$(git -C "$R" status --porcelain)" ]; }

@test "release: rejects a malformed version" {
  run rel y 0.2; [ "$status" -eq 1 ]; assert_contains "$output" "usage"
}

@test "release: refuses a dirty tree, a non-increasing version, an existing tag and a stale main" {
  touch "$R/junk"; run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "not clean"; rm "$R/junk"
  run rel y 0.1.0; [ "$status" -eq 1 ]; assert_contains "$output" "not greater"
  git -C "$R" tag v0.2.0; run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "already exists"
  git -C "$R" tag -d v0.2.0 >/dev/null
  git clone -q "$O" "$TD/other"
  ( cd "$TD/other" && git config user.email t@t.local && git config user.name t && echo x > x && git add x \
    && git commit -qm other && git push -q origin main )
  run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "not in sync"
  [ "$(cat "$R/VERSION")" = "0.1.0" ]
}

@test "release: an Unreleased section with only blank lines blocks the release" {
  ( cd "$R" && printf '%s\n' '# Changelog' '' '## Unreleased' '' '' '## 0.1.0 — 2026-10-01' '' '- first' > CHANGELOG.md \
    && git commit -qam empty && git push -q origin main )
  run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "Unreleased"; clean
}

@test "release: failing tests stop before any file changes" {
  TESTCMD=false run rel y 0.2.0
  [ "$status" -eq 1 ]; assert_contains "$output" "tests failed"; clean; [ "$(cat "$R/VERSION")" = "0.1.0" ]
}

@test "release: declining the push keeps the local commit and tag and prints how to undo" {
  run rel n 0.2.0
  [ "$status" -eq 0 ]; assert_contains "$output" "git tag -d v0.2.0 && git reset --hard HEAD~1"
  [ "$(cat "$R/VERSION")" = "0.2.0" ]
  [ "$(sed -n 3p "$R/CHANGELOG.md")" = "## Unreleased" ]
  [ "$(sed -n 5p "$R/CHANGELOG.md")" = "## 0.2.0 — $TODAY" ]
  [ "$(sed -n 7p "$R/CHANGELOG.md")" = "- feat: something" ]
  [ "$(git -C "$R" log -1 --format=%s)" = "chore(release): 0.2.0" ]
  [ "$(git -C "$R" cat-file -t v0.2.0)" = "tag" ]
  assert_fails git -C "$O" rev-parse -q --verify refs/tags/v0.2.0
}

@test "release: accepting pushes main and the annotated tag together; works from a subdirectory" {
  mkdir -p "$R/sub" && touch "$R/sub/.keep" && ( cd "$R" && git add -A && git commit -qm sub && git push -q origin main )
  run bash -c "cd '$R/sub' && printf 'y\n' | SIMLANE_RELEASE_TEST_CMD=true '$S' 0.2.0"
  [ "$status" -eq 0 ]; assert_contains "$output" "pushed v0.2.0"
  [ "$(git -C "$O" rev-parse main)" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(git -C "$O" cat-file -t v0.2.0)" = "tag" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/release.bats`
Expected: FAIL (exit 127).

- [ ] **Step 3: Implement** — `scripts/release.sh`:

```bash
#!/usr/bin/env bash
# Prepare and push a release: scripts/release.sh X.Y.Z
# preconditions → tests → date CHANGELOG + write VERSION → commit + tag → confirm → push.
# The tag push starts .github/workflows/release.yml (GitHub Release + Homebrew tap).
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)
fail() { echo "release: $*" >&2; exit 1; }

version_gt() {   # A B → success when X.Y.Z A is greater than B
  local IFS=.
  # shellcheck disable=SC2086  # split both versions on dots
  set -- $1 $2
  if [ "$1" -ne "$4" ]; then [ "$1" -gt "$4" ]; return; fi
  if [ "$2" -ne "$5" ]; then [ "$2" -gt "$5" ]; return; fi
  [ "$3" -gt "$6" ]
}

v=${1:-}
printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "usage: scripts/release.sh X.Y.Z"
root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$root"

# 1. preconditions — nothing is modified before all of them pass
[ "$(git symbolic-ref --short HEAD 2>/dev/null || true)" = main ] || fail "not on main"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean"
git fetch -q origin main --tags || fail "git fetch origin failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not in sync with origin/main"
cur=0.0.0
if [ -f VERSION ]; then cur=$(tr -d '[:space:]' < VERSION); fi
version_gt "$v" "$cur" || fail "$v is not greater than the current version $cur"
if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then fail "tag v$v already exists"; fi
if git ls-remote --exit-code --tags origin "refs/tags/v$v" >/dev/null 2>&1; then fail "tag v$v already exists on origin"; fi
"$HERE/changelog-section.sh" Unreleased CHANGELOG.md >/dev/null || fail "CHANGELOG.md needs a non-empty '## Unreleased' section"

# 2. tests
echo "release: running tests" >&2
bash -c "${SIMLANE_RELEASE_TEST_CMD:-bats tests/}" || fail "tests failed"

# 3. CHANGELOG + VERSION
today=$(date +%Y-%m-%d)
awk -v v="$v" -v d="$today" '
  !done && /^## Unreleased[[:space:]]*$/ { print "## Unreleased"; print ""; print "## " v " — " d; done = 1; next }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp
cat CHANGELOG.md.tmp > CHANGELOG.md
rm -f CHANGELOG.md.tmp
printf '%s\n' "$v" > VERSION

# 4. commit + annotated tag
git add CHANGELOG.md VERSION
git commit -q -m "chore(release): $v"
git tag -a "v$v" -m "simlane $v"

# 5. confirm, push
printf 'release: push main and v%s to origin? [y/N] ' "$v" >&2
ans=
read -r ans || true
case "$ans" in
  y|Y|yes) ;;
  *) echo "release: not pushed. To undo: git tag -d v$v && git reset --hard HEAD~1" >&2; exit 0 ;;
esac
git push -q --atomic origin main "v$v" || fail "push failed; the commit and tag are still local"
echo "release: pushed v$v. CI publishes the GitHub Release and updates the tap: https://github.com/ChoiHyeongu/simlane/actions" >&2
```

```bash
chmod +x scripts/release.sh
```

- [ ] **Step 4: Run tests**

Run: `bats tests/release.bats && bats tests/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/release.sh tests/release.bats
git commit -m "feat: add scripts/release.sh to cut a release

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: shellcheck clean-up and `ci.yml`

**Files:**
- Create: `.shellcheckrc`, `.github/workflows/ci.yml`
- Modify: `lib/common.sh` (SC2034 directive)

**Interfaces:**
- Produces: workflow `ci.yml` with triggers `push` (main), `pull_request`, `workflow_call`; job `test` that runs
  shellcheck on `bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh`, `actionlint`, and `bats tests/` with `/bin` first in
  `PATH` so `bash` is the stock 3.2. Task 9 calls it with `uses: ./.github/workflows/ci.yml`.

- [ ] **Step 1: See the current findings**

Run: `shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh`
Expected: SC1090 ×2 in `bin/simlane` (dynamic `source`), SC2034 ×4 in `lib/common.sh` (exit codes used by the files that
source it). Any finding in the new Task 1–7 files is a real issue: fix it in the code, not with a directive.

- [ ] **Step 2: Configure and fix**

`.shellcheckrc`:

```
shell=bash
# lib/*.sh and lib/cmd/*.sh are sourced through a loop over a computed path.
disable=SC1090,SC1091
```

In `lib/common.sh`, insert directly under the header comment (line 2), before the first assignment:

```bash
# shellcheck disable=SC2034  # the SIMLANE_EXIT_* codes are used by the files that source this one
```

Run: `shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Add the workflow** — `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
  workflow_call:

permissions:
  contents: read

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v5
      - name: Install tools
        env:
          HOMEBREW_NO_AUTO_UPDATE: "1"
        run: brew install bats-core shellcheck actionlint jq
      - name: shellcheck
        run: shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh
      - name: actionlint
        run: actionlint
      - name: bats on the stock /bin/bash 3.2
        run: |
          export PATH="/bin:/usr/bin:$PATH"
          bash --version | head -1 | grep -q 'version 3\.2' || { echo "expected bash 3.2, got: $(bash --version | head -1)"; exit 1; }
          bats tests/
```

- [ ] **Step 4: Verify locally**

Run: `actionlint && shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh && PATH="/bin:/usr/bin:$PATH" bats tests/`
Expected: no actionlint/shellcheck output; all bats tests pass.

- [ ] **Step 5: Commit**

```bash
git add .shellcheckrc lib/common.sh .github/workflows/ci.yml
git commit -m "ci: run bats, shellcheck and actionlint on macOS bash 3.2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: `release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/check-release.sh`, `scripts/changelog-section.sh`, `scripts/update-formula.sh`, `ci.yml`
  (`workflow_call`), secret `TAP_GITHUB_TOKEN`.
- Produces: on a `v*` tag push — verify → test → GitHub Release (skipped if it exists) → tarball sha256 → formula
  update committed in a local tap checkout → `brew install` + `brew test` + version check from that checkout → push
  the tap (skipped when `unchanged`).

- [ ] **Step 1: Write the workflow** — `.github/workflows/release.yml`:

```yaml
name: release

on:
  push:
    tags: ["v*"]

concurrency:
  group: release
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  verify:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - name: Tag matches VERSION and CHANGELOG
        run: scripts/check-release.sh "$GITHUB_REF_NAME"
      - name: Tag commit is on main
        run: git merge-base --is-ancestor "$GITHUB_SHA" origin/main

  test:
    needs: verify
    uses: ./.github/workflows/ci.yml

  publish:
    needs: test
    runs-on: macos-latest
    env:
      GH_TOKEN: ${{ github.token }}
      TAG: ${{ github.ref_name }}
      HOMEBREW_NO_AUTO_UPDATE: "1"
      HOMEBREW_NO_INSTALL_FROM_API: "1"
    steps:
      - uses: actions/checkout@v5
      - name: GitHub Release
        run: |
          if gh release view "$TAG" >/dev/null 2>&1; then
            echo "release $TAG already exists"
          else
            scripts/changelog-section.sh "${TAG#v}" > notes.md
            gh release create "$TAG" --title "simlane ${TAG#v}" --notes-file notes.md
          fi
      - name: Tarball sha256
        id: sha
        run: |
          url="https://github.com/${GITHUB_REPOSITORY}/archive/refs/tags/${TAG}.tar.gz"
          for i in 1 2 3 4 5; do
            if curl -fsSL "$url" -o src.tar.gz; then break; fi
            [ "$i" -lt 5 ] || exit 1
            sleep $((i * 5))
          done
          echo "sha256=$(shasum -a 256 src.tar.gz | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"
      - uses: actions/checkout@v5
        with:
          repository: ChoiHyeongu/homebrew-tap
          token: ${{ secrets.TAP_GITHUB_TOKEN }}
          path: tap
      - name: Update the formula (local commit only)
        id: formula
        run: |
          result=$(scripts/update-formula.sh tap/Formula/simlane.rb "${TAG#v}" "${{ steps.sha.outputs.sha256 }}")
          echo "result=$result" >> "$GITHUB_OUTPUT"
          if [ "$result" = updated ]; then
            git -C tap config user.name "github-actions[bot]"
            git -C tap config user.email "41898282+github-actions[bot]@users.noreply.github.com"
            git -C tap commit -qam "simlane ${TAG#v}"
          fi
      - name: brew install and test from the updated tap
        run: |
          brew tap choihyeongu/tap "$PWD/tap"
          brew install choihyeongu/tap/simlane
          brew test choihyeongu/tap/simlane
          [ "$(simlane --version)" = "${TAG#v}" ]
      - name: Push the tap
        if: steps.formula.outputs.result == 'updated'
        run: git -C tap push -q origin HEAD
```

- [ ] **Step 2: Lint**

Run: `actionlint`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: publish GitHub Release and update the Homebrew tap on tag push

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Modify: `README.md`, `README.ko.md`, `CLAUDE.md`, `CHANGELOG.md`
- Create: `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`

**Interfaces:** none (docs only). Must not mention `install-claude-hooks.sh` anywhere except `CHANGELOG.md`.

- [ ] **Step 1: README.md** — replace the `## Install` section body with:

````markdown
```sh
brew install choihyeongu/tap/simlane
simlane setup --hooks   # links the Claude Code skill and registers the hooks; omit --hooks for the skill only
```

Upgrade with `brew upgrade simlane`; the skill link and the hooks point at Homebrew's `opt/simlane` path and keep
working. To remove: `brew uninstall simlane`, `rm ~/.claude/skills/simlane`, and delete the `simlane claude-hook`
entries from `~/.claude/settings.json` (left alone they do nothing).

Working on simlane itself: see [CONTRIBUTING.md](CONTRIBUTING.md).
````

In `## Claude Code integration`, replace the sentence starting with ``scripts/install-claude-hooks.sh` registers`` by
``simlane setup --hooks` registers`` (keep the rest of the paragraph).

- [ ] **Step 2: README.ko.md** — same two edits in Korean:

````markdown
```sh
brew install choihyeongu/tap/simlane
simlane setup --hooks   # Claude Code 스킬 링크 + 훅 등록 (스킬만 원하면 --hooks 생략)
```

`brew upgrade simlane`으로 업그레이드합니다. 스킬 링크와 훅은 Homebrew의 `opt/simlane` 경로를 가리키므로 업그레이드 후에도
그대로 동작합니다. 제거: `brew uninstall simlane`, `rm ~/.claude/skills/simlane`, `~/.claude/settings.json`에서
`simlane claude-hook` 항목 삭제(남겨 둬도 아무 일도 하지 않습니다).

simlane 자체를 개발하려면 [CONTRIBUTING.md](CONTRIBUTING.md)를 보세요.
````

and ``scripts/install-claude-hooks.sh`가`` → ``simlane setup --hooks`가``.

- [ ] **Step 3: CONTRIBUTING.md**

````markdown
# Contributing to simlane

## Setup

```sh
git clone https://github.com/ChoiHyeongu/simlane.git
cd simlane
scripts/install.sh            # ~/bin/simlane → this checkout, plus the Claude Code skill (add --hooks for hooks)
brew install bats-core shellcheck actionlint
```

If you also have the Homebrew formula installed, whichever `simlane setup` ran last owns the skill link and hooks.

## Rules

- **bash 3.2** (macOS `/bin/bash`): no `declare -A`, `mapfile`, `${var,,}`, `local -n`; empty arrays expand as
  `${arr[@]+"${arr[@]}"}`.
- Namespace `simlane::`, subcommands `cmd_*`, one subcommand per file in `lib/cmd/`.
- Exit codes, `.simlane.json` fields, `SIMLANE_*` variables and CLI flags are API. Changing them is a breaking change.
- `simlane` only ever touches simulators named `Simlane N`.
- Never run `simlane up/down/gc` against your machine as a test; the suite uses fakes in `tests/fakes/`.

## Tests

```sh
bats tests/
shellcheck bin/simlane lib/*.sh lib/cmd/*.sh scripts/*.sh
actionlint
```

- Write the failing test first.
- Assert with `[ … ]` or the helpers in `tests/test_helper.bash` (`assert_contains`, `assert_not_contains`,
  `assert_endswith`, `assert_fails`). Under bash 3.2 a failing `[[ ]]` on a non-final line, and `! cmd` on any line,
  do **not** fail a bats test.
- CI runs the same three commands on `macos-latest` with the stock `/bin/bash`.

## Pull requests

- Conventional Commits (`feat:`, `fix:`, `docs:` …); `feat!:` / `BREAKING CHANGE:` for API changes.
- Add a line under `## Unreleased` in `CHANGELOG.md` for anything a user would notice.

## Releasing (maintainers)

```sh
scripts/release.sh 0.3.0
```

The script checks that you are on a clean `main` in sync with `origin`, runs the tests, dates the `## Unreleased`
section, writes `VERSION`, commits, tags `v0.3.0`, and asks before pushing. The tag push runs
`.github/workflows/release.yml`: it verifies tag/VERSION/CHANGELOG, runs CI, creates the GitHub Release from the
CHANGELOG section, and updates `Formula/simlane.rb` in
[ChoiHyeongu/homebrew-tap](https://github.com/ChoiHyeongu/homebrew-tap) after installing and testing it on the runner.

SemVer; while 0.x a breaking change bumps the minor version.

| failure | what is public | recovery |
| --- | --- | --- |
| `release.sh` checks or tests | nothing | fix and re-run |
| push declined | nothing | run the printed undo command |
| CI verify/test | the tag | `git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`, fix, release the same version |
| CI publish (e.g. expired token) | the GitHub Release; the tap still serves the previous version | fix the cause, `gh run rerun <run-id>` |
| a released version is broken | everything | never move a published tag; release a patch |

`TAP_GITHUB_TOKEN` is a fine-grained personal access token with *Contents: read and write* on `homebrew-tap` only.
It expires; renew it (at most yearly) with `gh secret set TAP_GITHUB_TOKEN --repo ChoiHyeongu/simlane`.
````

- [ ] **Step 4: Issue templates**

`.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Something simlane did wrong
labels: bug
---

**What happened**

**What you expected**

**Steps to reproduce**

**Environment**
- `simlane --version`:
- macOS / Xcode:
- Installed via: Homebrew / git clone
- `simlane status` output:
```

`.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature request
about: Something simlane should do
labels: enhancement
---

**Problem** — what are you trying to do, and what gets in the way?

**Proposal**

**Alternatives you considered**
```

- [ ] **Step 5: CLAUDE.md** — in the Layout table: `lib/cmd/*.sh` row lists
  `prepare up down status env metro gc init setup version claude-hook`; replace the `scripts/` row with
  `| `scripts/` | `install.sh` (contributor install, then `simlane setup`), `release.sh`, `changelog-section.sh`, `check-release.sh`, `update-formula.sh` |`;
  skill row says `(linked into ~/.claude/skills/simlane by simlane setup)`; add a row
  `| `.github/workflows/` | `ci.yml` (bats, shellcheck, actionlint on macOS bash 3.2), `release.yml` (tag → Release + Homebrew tap) |`.
  Replace the `## Releasing` body with:

```markdown
Add user-visible changes under `## Unreleased` in `CHANGELOG.md` as you go. To release, run `scripts/release.sh X.Y.Z`
on a clean, pushed `main` (only when the maintainer asks); it tags and pushes, and `release.yml` publishes the GitHub
Release and updates `ChoiHyeongu/homebrew-tap`. Details and recovery: `CONTRIBUTING.md`.
```

- [ ] **Step 6: CHANGELOG.md** — under `## Unreleased` add:

```markdown
- Homebrew tap: `brew install choihyeongu/tap/simlane`.
- CI on macOS bash 3.2 (bats, shellcheck, actionlint) and tag-driven releases.
```

- [ ] **Step 7: Verify**

Run: `grep -rn "install-claude-hooks" --exclude=CHANGELOG.md --exclude-dir=.git --exclude-dir=superpowers . ; bats tests/`
Expected: grep prints nothing; all tests pass (including `tests/rename_guard.bats`).

- [ ] **Step 8: Commit**

```bash
git add README.md README.ko.md CLAUDE.md CHANGELOG.md CONTRIBUTING.md .github/ISSUE_TEMPLATE
git commit -m "docs: document Homebrew install, contributing and releasing

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Tap bootstrap and first release (maintainer-run; each outward step needs the maintainer's go-ahead)

**Files:**
- Create (in a new repo `ChoiHyeongu/homebrew-tap`): `Formula/simlane.rb`, `README.md`

**Interfaces:**
- Consumes: everything above merged to `main`.
- Produces: public tap repo; secret `TAP_GITHUB_TOKEN` on `ChoiHyeongu/simlane`; tag `v0.2.0` with a GitHub Release and
  the tap formula at 0.2.0.

- [ ] **Step 1: Merge** — open a PR from `feature/release-pipeline`, wait for `ci` to pass on it (first real run of
  `ci.yml`), merge to `main`.

- [ ] **Step 2: Create the tap repo** (asks the maintainer first — creates a public repository)

```bash
gh repo create ChoiHyeongu/homebrew-tap --public --description "Homebrew formulae by ChoiHyeongu" --clone
```

- [ ] **Step 3: Seed the formula** — inside the clone, seeded at v0.1.0 so `update-formula.sh` has lines to rewrite
  (CI replaces them on the first release):

```bash
mkdir -p Formula
SHA=$(curl -fsSL https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256 | cut -d' ' -f1)
```

`Formula/simlane.rb` (substitute the computed `$SHA`):

```ruby
class Simlane < Formula
  desc "One iOS simulator + Metro lane per git worktree for parallel React Native work"
  homepage "https://github.com/ChoiHyeongu/simlane"
  url "https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "<the value of $SHA>"
  license "MIT"

  depends_on "jq"
  depends_on :macos
  depends_on "tmux"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/simlane"
  end

  def caveats
    <<~EOS
      Link the Claude Code skill and register the session hooks:
        simlane setup --hooks
      To remove them later: rm ~/.claude/skills/simlane, and delete the
      "simlane claude-hook" entries from ~/.claude/settings.json.
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/simlane --version").strip
  end
end
```

`README.md`:

````markdown
# homebrew-tap

```sh
brew install choihyeongu/tap/simlane
```

Formulae here are updated by the release workflows of their projects.
````

Run: `ruby -c Formula/simlane.rb` → `Syntax OK`; then commit `feat: add simlane formula` and push (maintainer go-ahead).

- [ ] **Step 4: Token** — the maintainer creates a fine-grained PAT in GitHub settings (Repository access: only
  `ChoiHyeongu/homebrew-tap`; Permissions: Contents read and write; expiry ≤ 1 year) and stores it:

```bash
gh secret set TAP_GITHUB_TOKEN --repo ChoiHyeongu/simlane
```

- [ ] **Step 5: Release 0.2.0** — on an up-to-date `main`:

```bash
scripts/release.sh 0.2.0
```

Answer `y` at the prompt (maintainer). Then watch `gh run watch` for the `release` workflow; it must end green.

- [ ] **Step 6: Verify as a user**

```bash
brew update && brew install choihyeongu/tap/simlane && simlane --version
```

Expected: `0.2.0`. Then `brew info choihyeongu/tap/simlane` shows 0.2.0, and the GitHub Release `v0.2.0` shows the
CHANGELOG section.

- [ ] **Step 7: Update the maintainer's own install** — the maintainer's machine still has the 0.1.0 clone install with
  hooks pointing at `$HOME/bin/simlane`. Run `simlane setup --hooks` from the brew install: it replaces the old entry
  (Task 4) and relinks the skill to `opt/` (Task 3). Remove `~/bin/simlane` and the old clone only if the maintainer
  wants to.

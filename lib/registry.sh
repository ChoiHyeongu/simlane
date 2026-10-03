#!/usr/bin/env bash
# Lane registry: ~/.config/simlane/lanes.json. Writes go through a temp file + mv (atomic). Callers hold the lock.

simlane::registry_path() { printf '%s/lanes.json\n' "$(simlane::config_dir)"; }

simlane::registry_read() {
  local f; f=$(simlane::registry_path)
  [ -f "$f" ] || printf '{"version":1,"lanes":{}}\n' > "$f"
  cat "$f"
}

simlane::registry_write() {   # JSON
  local f tmp; f=$(simlane::registry_path); tmp="$f.tmp.$$"
  printf '%s\n' "$1" | jq . > "$tmp" && mv "$tmp" "$f"
}

simlane::dir_inode() { stat -f %i "$1"; }

simlane::registry_find_by_worktree() {   # PATH → LANE | empty
  simlane::registry_read | jq -r --arg w "$1" '.lanes | to_entries[] | select(.value.worktree == $w) | .key' | head -n1
}

simlane::registry_get() {   # LANE FIELD → value | empty
  simlane::registry_read | jq -r --arg s "$1" --arg f "$2" '.lanes[$s][$f] // empty'
}

simlane::registry_update() {   # LANE FIELD VALUE
  simlane::registry_write "$(simlane::registry_read | jq --arg s "$1" --arg f "$2" --arg v "$3" '.lanes[$s][$f] = $v')"
}

simlane::registry_release() {   # LANE
  simlane::registry_write "$(simlane::registry_read | jq --arg s "$1" 'del(.lanes[$s])')"
}

simlane::registry_lanes() {   # assigned lane numbers, ascending, one per line
  simlane::registry_read | jq -r '.lanes | keys_unsorted[]' | sort -n
}

simlane::registry_reclaim_dead() {   # release lanes whose worktree directory is gone; print the released lane numbers
  local s w
  for s in $(simlane::registry_lanes); do
    w=$(simlane::registry_get "$s" worktree)
    if [ -n "$w" ] && [ ! -d "$w" ]; then
      simlane::registry_release "$s"
      printf '%s\n' "$s"
    fi
  done
  return 0
}

simlane::registry_allocate() {   # WT INODE PROJECT APPDIR BUNDLEID KEY → LANE (return 3 when all lanes are in use)
  local w=$1 inode=$2 project=$3 appDir=$4 bundleId=$5 key=$6 max s existing now
  existing=$(simlane::registry_find_by_worktree "$w")
  if [ -n "$existing" ]; then printf '%s\n' "$existing"; return 0; fi
  simlane::registry_reclaim_dead >/dev/null
  max=$(simlane::config_get .maxLanes)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  s=1
  while [ "$s" -le "$max" ]; do
    if [ -z "$(simlane::registry_get "$s" worktree)" ]; then
      simlane::registry_write "$(simlane::registry_read | jq \
        --arg s "$s" --arg w "$w" --arg i "$inode" --arg p "$project" --arg a "$appDir" --arg b "$bundleId" --arg k "$key" --arg t "$now" \
        '.lanes[$s] = {worktree:$w, inode:$i, project:$p, appDir:$a, bundleId:$b, jsLocationKey:$k, since:$t}')"
      printf '%s\n' "$s"
      return 0
    fi
    s=$((s + 1))
  done
  return "$SIMLANE_EXIT_EXHAUSTED"
}

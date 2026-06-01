#!/usr/bin/env bats
# Tests for skills/squad-spawn/scripts/spawn.sh
#
# spawn.sh pre-creates one git worktree per ACTIVE role for Multi-use mode.
# It launches no teammate and bakes no prompt. These tests cover the preflight
# refusals (missing goal/roster, missing jq/git, Agent Teams off, wrong mode,
# not a git repo) and idempotent worktree creation.

setup() {
  SPAWN="$BATS_TEST_DIRNAME/../skills/squad-spawn/scripts/spawn.sh"
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email t@example.com
  git config user.name tester
  echo "# test" > README.md
  git add . && git commit -q -m init
  mkdir -p .squad
  printf -- '---\nmode: multi-use\n---\n' > .squad/goal.md
  cat > .squad/roster.json <<'JSON'
{ "roles": [
    { "name": "alpha", "active": true,  "file_scope": ["a/**"] },
    { "name": "beta",  "active": true,  "file_scope": ["b/**"] },
    { "name": "gamma", "active": false, "file_scope": ["g/**"] }
] }
JSON
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
}

teardown() {
  cd /
  rm -rf "$REPO"
}

# --- happy path --------------------------------------------------------------

@test "creates one worktree per ACTIVE role (inactive excluded)" {
  run "$SPAWN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"role":"alpha"'* ]]
  [[ "$output" == *'"role":"beta"'* ]]
  [[ "$output" != *'"role":"gamma"'* ]]
  [[ "$output" == *'"created":2'* ]]
  [ -d .claude/worktrees/alpha ]
  [ -d .claude/worktrees/beta ]
  [ ! -d .claude/worktrees/gamma ]
}

@test "second run is idempotent (reports exists, creates nothing)" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  run "$SPAWN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"exists"'* ]]
  [[ "$output" == *'"created":0'* ]]
  [[ "$output" == *'"existed":2'* ]]
}

# --- preflight refusals ------------------------------------------------------

@test "refuses when goal is missing" {
  rm -f .squad/goal.md
  run "$SPAWN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no squad goal"* ]]
}

@test "refuses when roster is missing" {
  rm -f .squad/roster.json
  run "$SPAWN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no roster"* ]]
}

@test "refuses when Agent Teams is not enabled" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0
  run "$SPAWN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENT_TEAMS"* ]]
}

@test "refuses when mode is not multi-use" {
  printf -- '---\nmode: one-time\n---\n' > .squad/goal.md
  run "$SPAWN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"multi-use mode only"* ]]
}

@test "refuses when not inside a git repository" {
  rm -rf .git
  run "$SPAWN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git repository"* ]]
}

@test "refuses when jq is missing (preflight, before git check)" {
  bindir="$(mktemp -d)"
  for b in bash git; do ln -s "$(command -v "$b")" "$bindir/$b"; done
  run env -i PATH="$bindir" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
    bash "$SPAWN" "$REPO/.squad/roster.json" "$REPO/.squad/goal.md"
  rm -rf "$bindir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "refuses when git is missing (preflight)" {
  bindir="$(mktemp -d)"
  for b in bash jq; do ln -s "$(command -v "$b")" "$bindir/$b"; done
  run env -i PATH="$bindir" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
    bash "$SPAWN" "$REPO/.squad/roster.json" "$REPO/.squad/goal.md"
  rm -rf "$bindir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git is required"* ]]
}

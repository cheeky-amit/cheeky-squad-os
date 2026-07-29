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

# --- collect -------------------------------------------------------------
#
# `spawn.sh collect` pulls each active role's engagement record
# (.squad/role-plan-<role>.md, hard rule #11) out of its worktree — created
# by real `git worktree add` via a prior `run "$SPAWN"`, per this file's
# existing fixture pattern — and into the project root's .squad/.

@test "collect: copies a newer worktree record to the project root" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  mkdir -p .claude/worktrees/alpha/.squad
  printf -- '---\nrole: alpha\ncreated: 2026-01-01T00:00:00Z\nstatus: active\n---\n# Engagement record\n' \
    > .claude/worktrees/alpha/.squad/role-plan-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"role":"alpha","artifact":".squad/role-plan-alpha.md","status":"copied"}'* ]]
  [[ "$output" == *'"collected":1'* ]]
  [ -f .squad/role-plan-alpha.md ]
  grep -q "role: alpha" .squad/role-plan-alpha.md
}

@test "collect: leaves a newer root record alone" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  mkdir -p .claude/worktrees/alpha/.squad
  printf 'stale worktree copy\n' > .claude/worktrees/alpha/.squad/role-plan-alpha.md
  touch -t 202601010000 .claude/worktrees/alpha/.squad/role-plan-alpha.md

  mkdir -p .squad
  printf 'authoritative root copy\n' > .squad/role-plan-alpha.md
  touch -t 202606010000 .squad/role-plan-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"role":"alpha","artifact":".squad/role-plan-alpha.md","status":"skipped-not-newer"}'* ]]
  [ "$(cat .squad/role-plan-alpha.md)" = "authoritative root copy" ]
}

@test "collect: skips a role with no worktree" {
  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"role":"alpha","artifact":".squad/role-plan-alpha.md","status":"skipped-no-worktree"}'* ]]
  [[ "$output" == *'{"role":"beta","artifact":".squad/role-plan-beta.md","status":"skipped-no-worktree"}'* ]]
  [ ! -f .squad/role-plan-alpha.md ]
  [ ! -f .squad/role-plan-beta.md ]
}

@test "collect: copies only the two named contract artifacts, never other .squad/ paths" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  mkdir -p .claude/worktrees/alpha/.squad/world
  printf 'record\n' > .claude/worktrees/alpha/.squad/role-plan-alpha.md
  printf 'claims\n' > .claude/worktrees/alpha/.squad/world/claims-alpha.md
  printf 'decoy outbox\n' > .claude/worktrees/alpha/.squad/role-comm-alpha--beta.md
  printf 'decoy sibling\n' > .claude/worktrees/alpha/.squad/world/claims-beta.md
  printf 'decoy flat claims\n' > .claude/worktrees/alpha/.squad/claims-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [ -f .squad/role-plan-alpha.md ]
  [ -f .squad/world/claims-alpha.md ]
  [ ! -f .squad/role-comm-alpha--beta.md ]
  [ ! -f .squad/world/claims-beta.md ]
  [ ! -f .squad/claims-alpha.md ]
}

# A worktree role's claims file is invisible at the project root until this
# runs — and an uncollected ledger is what the NEXT dispatch's world index is
# computed from, so a silent miss propagates.
@test "collect: brings back a worktree role's claims file, creating world/ on demand" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  [ ! -d .squad/world ]
  mkdir -p .claude/worktrees/alpha/.squad/world
  printf '## Belief: k\n\nClaim: c\nSource: s\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n' \
    > .claude/worktrees/alpha/.squad/world/claims-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [ -f .squad/world/claims-alpha.md ]
  printf '%s\n' "$output" | grep '"artifact":".squad/world/claims-alpha.md"' | jq -e '.status == "copied"'
}

@test "collect: a role with a record but no claims file reports each artifact separately" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  mkdir -p .claude/worktrees/alpha/.squad
  printf 'record\n' > .claude/worktrees/alpha/.squad/role-plan-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [ -f .squad/role-plan-alpha.md ]
  [ ! -f .squad/world/claims-alpha.md ]
  printf '%s\n' "$output" | grep '"artifact":".squad/role-plan-alpha.md"' | jq -e '.status == "copied"'
  printf '%s\n' "$output" | grep '"artifact":".squad/world/claims-alpha.md"' | jq -e '.status != "copied"'
}

@test "collect: emits valid JSON on every line" {
  run "$SPAWN"; [ "$status" -eq 0 ]
  mkdir -p .claude/worktrees/alpha/.squad
  printf 'record\n' > .claude/worktrees/alpha/.squad/role-plan-alpha.md

  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq empty
  done <<< "$output"
}

@test "collect: exits 0 when there is nothing to collect" {
  cat > .squad/roster.json <<'JSON'
{ "roles": [
    { "name": "gamma", "active": false, "file_scope": ["g/**"] }
] }
JSON
  run "$SPAWN" collect
  [ "$status" -eq 0 ]
  [[ "$output" == *'"collected":0'* ]]
  [[ "$output" == *'"errors":0'* ]]
}

# --- The workflow dispatch template's world-model wiring (hard rule #13) --------
#
# templates/squad-dispatch.workflow.js is shipped JavaScript that CI otherwise
# only `node --check`s — a syntax check proves nothing about whether
# args.worldIndex actually reaches the spawned prompt. It once did not: the
# command built the field and the template never read it, so the belief ledger
# was silently absent on the whole workflow path. And a rename that keeps the
# file parseable (an unused-variable autofix, say) reintroduces exactly that,
# invisibly. So: render the prompt for real and assert on the text.

# render_workflow_prompt <args-json> → the spawnPrompt() output for one role.
# Evaluates the template's DEFINITIONS only (everything before the runtime
# phase call), so no agent is ever dispatched.
render_workflow_prompt() {
  node --input-type=module -e '
    import fs from "fs";
    let src = fs.readFileSync(process.argv[1], "utf8").replace(/^export /gm, "");
    src = src.slice(0, src.indexOf("phase(\"Dispatch\")"));
    const args = JSON.parse(process.argv[2]);
    const render = new Function("args", "log",
      "return (()=>{" + src +
      "\nreturn spawnPrompt({name:\"scout\",roleGoal:\"RG\",fileScope:[\"src/**\"],task:\"T\"});})();");
    process.stdout.write(render(args, () => {}));
  ' "$TEMPLATE" "$1"
}

@test "workflow template: args.worldIndex reaches the spawned prompt verbatim" {
  command -v node >/dev/null || skip "node not installed"
  TEMPLATE="$BATS_TEST_DIRNAME/../templates/squad-dispatch.workflow.js"
  IDX='## World model\n- rate-limit: 100rps. — scout [confirmed, observed 2026-07-01]\n\nInvalid: 0 (excluded from every projection)'
  run render_workflow_prompt "{\"goal\":\"G\",\"roles\":[{\"name\":\"scout\"}],\"worldIndex\":\"$IDX\"}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Shared world model"* ]]
  [[ "$output" == *"- rate-limit: 100rps. — scout [confirmed, observed 2026-07-01]"* ]]
  [[ "$output" == *".squad/world/claims-scout.md"* ]]
}

@test "workflow template: an absent worldIndex renders no world section at all" {
  command -v node >/dev/null || skip "node not installed"
  TEMPLATE="$BATS_TEST_DIRNAME/../templates/squad-dispatch.workflow.js"
  run render_workflow_prompt '{"goal":"G","roles":[{"name":"scout"}]}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Shared world model"* ]]
  [[ "$output" != *"claims-scout.md"* ]]
}

@test "workflow template: a blank worldIndex renders no world section either" {
  command -v node >/dev/null || skip "node not installed"
  TEMPLATE="$BATS_TEST_DIRNAME/../templates/squad-dispatch.workflow.js"
  run render_workflow_prompt '{"goal":"G","roles":[{"name":"scout"}],"worldIndex":"   \n  "}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Shared world model"* ]]
}

#!/usr/bin/env bats
# Table-driven tests for hooks/permission-request.sh
#
# The hook auto-APPROVES a subagent Edit/Write inside the role's file_scope
# (emits a decision JSON) and DEFERS everything else (no output → user is
# prompted). These tests assert allow-vs-defer across the v1 decision matrix,
# including the negative paths the manual smoke test does not cover:
#   in-scope allow · out-of-scope defer · Bash defer · main-session defer ·
#   unknown-role defer · single-segment glob semantics · ".." traversal defer ·
#   missing-jq fail-open.

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/permission-request.sh"
  PROJECT_DIR="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR/.squad"
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{
  "roles": [
    { "name": "reporter", "file_scope": ["reports/**", ".squad/role-comm-reporter--*"] },
    { "name": "rootdoc",  "file_scope": ["*.md"] },
    { "name": "datakeeper", "file_scope": ["data/*"] },
    { "name": "builder",  "file_scope": ["build/**", ".squad/workspaces/builder/**"],
      "environment": { "workspace": ".squad/workspaces/builder/" } },
    { "name": "broadscope", "file_scope": ["**"],
      "environment": { "workspace": ".squad/workspaces/broadscope/" } },
    { "name": "greedy", "file_scope": ["**"],
      "environment": { "workspace": ".squad/" } }
  ]
}
JSON
}

teardown() {
  rm -rf "$PROJECT_DIR"
}

# Run the hook with a JSON payload on stdin; $output captures stdout+stderr.
run_hook() {
  run bash -c "printf '%s' '$1' | '$HOOK'"
}

# --- allow path --------------------------------------------------------------

@test "in-scope Write is auto-approved (relative path)" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"reports/audit.md"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "in-scope Edit is auto-approved (absolute path inside project)" {
  run_hook '{"agent_type":"reporter","tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/reports/sub/note.md"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "single-segment glob matches a root file" {
  run_hook '{"agent_type":"rootdoc","tool_name":"Write","tool_input":{"file_path":"notes.md"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

# --- defer paths (no output) -------------------------------------------------

@test "out-of-scope path defers" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "single-segment glob does NOT match a nested file (defers)" {
  run_hook '{"agent_type":"rootdoc","tool_name":"Write","tool_input":{"file_path":"src/notes.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- hand-off manifest channel (role-comm outbox scope) ------------------------

@test "writing the role's own hand-off outbox is auto-approved" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-reporter--builder.md"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "writing ANOTHER role's hand-off outbox defers (no forged hand-offs)" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-builder--reporter.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- mid-path glob semantics ("*" must not cross "/") --------------------------

@test "mid-path glob matches a direct child" {
  run_hook '{"agent_type":"datakeeper","tool_name":"Write","tool_input":{"file_path":"data/export.csv"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "mid-path glob does NOT match a nested file (defers)" {
  run_hook '{"agent_type":"datakeeper","tool_name":"Write","tool_input":{"file_path":"data/sub/secret.csv"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mid-path glob does NOT match a deeply nested file (defers)" {
  run_hook '{"agent_type":"datakeeper","tool_name":"Write","tool_input":{"file_path":"data/a/b/c.csv"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mid-path glob does NOT match a shallower path (defers)" {
  run_hook '{"agent_type":"datakeeper","tool_name":"Write","tool_input":{"file_path":"data"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Bash defers for a role with no sandbox (no environment.workspace)" {
  run_hook '{"agent_type":"reporter","tool_name":"Bash","tool_input":{"command":"mkdir -p reports/x"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- in-sandbox Bash scaffolding (Surface 2) ---------------------------------

@test "in-sandbox mkdir is auto-approved (relative path)" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"mkdir -p .squad/workspaces/builder/outputs"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "in-sandbox cp with both operands inside the workspace is auto-approved" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"cp .squad/workspaces/builder/a .squad/workspaces/builder/b"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "in-sandbox touch via absolute path inside the project is auto-approved" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"touch '"$PROJECT_DIR"'/.squad/workspaces/builder/scratch/x"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "Bash operand OUTSIDE the sandbox defers" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"mkdir -p src/foo"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Bash cp with a source outside the project defers" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"cp /etc/passwd .squad/workspaces/builder/p"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "destructive verb (rm) defers even inside the sandbox" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"rm -rf .squad/workspaces/builder/outputs"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Bash with a shell metacharacter defers" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"mkdir -p .squad/workspaces/builder/a && rm -rf /"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Bash with a '..' traversal inside the workspace defers" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"mkdir -p .squad/workspaces/builder/../../../etc/x"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bare verb with no operand defers" {
  run_hook '{"agent_type":"builder","tool_name":"Bash","tool_input":{"command":"mkdir"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "main-session call (no agent_type) defers" {
  run_hook '{"tool_name":"Write","tool_input":{"file_path":"reports/audit.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unknown role defers" {
  run_hook '{"agent_type":"ghost","tool_name":"Write","tool_input":{"file_path":"reports/audit.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "relative '..' traversal defers even though it prefixes an in-scope glob" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"reports/../secrets.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "leading '..' traversal defers" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"../outside.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absolute path outside the project defers" {
  run_hook '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"/etc/passwd"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing jq fails open (defers, never auto-approves)" {
  # PATH with only bash + cat (no jq). The hook must defer rather than approve.
  bindir="$(mktemp -d)"
  for b in bash cat; do ln -s "$(command -v "$b")" "$bindir/$b"; done
  run env -i PATH="$bindir" CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
    bash "$HOOK" <<< '{"agent_type":"reporter","tool_name":"Write","tool_input":{"file_path":"reports/audit.md"}}'
  rm -rf "$bindir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the .squad/ structural reservation (v0.4.1) ------------------------------
#
# Regression suite for the forgery hole: before the reservation, .squad/ paths
# were matched against file_scope like any other path, so a role scoped "**"
# auto-approved writes to ANOTHER role's outbox, another role's goal, the squad
# goal, the roster, and verification.md. The pre-existing "no forged hand-offs"
# test above passes only because `reporter` happens to be narrowly scoped.
#
# The reservation: under .squad/, file_scope is never consulted. A role gets
# exactly the paths derived from its own sanitized agent_type.

@test "reservation: broad-scope role CANNOT forge another role's outbox" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-reporter--broadscope.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT write another role's role goal" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/role-goal-reporter.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT overwrite the squad goal" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/goal.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT rewrite the roster" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/roster.json"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT write verification.md (hard rule #10)" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/verification.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT write another role's sandbox" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/workspaces/builder/out.txt"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: broad-scope role CANNOT write a parked squad" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/squads/old-initiative/goal.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: a role's OWN outbox is granted structurally, without file_scope" {
  # `greedy` never registers an outbox glob; the grant is derived, not declared.
  run_hook '{"agent_type":"greedy","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-greedy--reporter.md"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "reservation: a role's OWN sandbox still auto-approves (hard rule #8 intact)" {
  run_hook '{"agent_type":"builder","tool_name":"Write","tool_input":{"file_path":".squad/workspaces/builder/inputs/x.csv"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "reservation: a workspace declared as '.squad/' grants nothing extra" {
  # A roster that points a sandbox at .squad/ itself must not swallow the
  # reserved contract paths through the workspace grant.
  run_hook '{"agent_type":"greedy","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-reporter--greedy.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: a workspace declared as '.squad/' cannot reach the goal" {
  run_hook '{"agent_type":"greedy","tool_name":"Write","tool_input":{"file_path":".squad/goal.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: unregistered agent gets no .squad/ grant" {
  run_hook '{"agent_type":"ghost","tool_name":"Write","tool_input":{"file_path":".squad/role-comm-ghost--reporter.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reservation: does not disturb ordinary work product (broad scope still works)" {
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "reservation: an unreserved .squad/ path defers even for a broad scope" {
  # Nothing owns .squad/scratch.md — under the reservation it is not grantable.
  run_hook '{"agent_type":"broadscope","tool_name":"Write","tool_input":{"file_path":".squad/scratch.md"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

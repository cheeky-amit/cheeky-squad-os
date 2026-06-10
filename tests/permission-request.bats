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
    { "name": "reporter", "file_scope": ["reports/**"] },
    { "name": "rootdoc",  "file_scope": ["*.md"] },
    { "name": "datakeeper", "file_scope": ["data/*"] },
    { "name": "builder",  "file_scope": ["build/**", ".squad/workspaces/builder/**"],
      "environment": { "workspace": ".squad/workspaces/builder/" } }
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

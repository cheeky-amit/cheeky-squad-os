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
    { "name": "rootdoc",  "file_scope": ["*.md"] }
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
  [[ "$output" == *allow* ]]
}

@test "in-scope Edit is auto-approved (absolute path inside project)" {
  run_hook '{"agent_type":"reporter","tool_name":"Edit","tool_input":{"file_path":"'"$PROJECT_DIR"'/reports/sub/note.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *allow* ]]
}

@test "single-segment glob matches a root file" {
  run_hook '{"agent_type":"rootdoc","tool_name":"Write","tool_input":{"file_path":"notes.md"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *allow* ]]
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

@test "Bash always defers (never auto-approved in v1)" {
  run_hook '{"agent_type":"reporter","tool_name":"Bash","tool_input":{"command":"rm -rf reports"}}'
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

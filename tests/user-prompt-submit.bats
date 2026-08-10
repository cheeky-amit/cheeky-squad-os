#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/user-prompt-submit.sh"
  PROJECT_DIR="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
}

teardown() {
  rm -rf "$PROJECT_DIR"
  if [ -n "${PLUGIN_DIR:-}" ]; then
    rm -rf "$PLUGIN_DIR"
  fi
}

run_hook() {
  run bash -c "printf '%s' '{\"prompt\":\"continue\"}' | '$HOOK'"
}

context() {
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext'
}

publish_goal() {
  mkdir -p "$PROJECT_DIR/.squad"
  printf '%s\n' '# Goal' '' "$1" > "$PROJECT_DIR/.squad/goal.md"
}

publish_manifest() {
  printf '%s\n' "$1" > "$PROJECT_DIR/.squad/manifest.json"
}

publish_plugin_snapshot() {
  PLUGIN_DIR="$(mktemp -d)"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR/.squad/context"
  printf '%s\n' '{"schema_version":2,"squad":{"id":"portable.demo","name":"Demo"},"execution_mode":"one-time","destination":"plugin","providers":["claude","codex"],"runtime_owner":"claude","export_version":"1.1.0"}' \
    > "$PLUGIN_DIR/.squad/manifest.json"
  printf '%s\n' '{"schema_version":1,"squad_goal":{"source":".squad/goal.md","status":"included","snapshot":"context/squad-goal.md"},"role_goals":[]}' \
    > "$PLUGIN_DIR/.squad/context/index.json"
  printf '%s\n' '# Vendored goal' '' 'Use the portable snapshot only.' \
    > "$PLUGIN_DIR/.squad/context/squad-goal.md"
}

@test "legacy authoring goal still emits the per-prompt reminder" {
  publish_goal 'Keep the legacy outcome in scope.'
  run_hook
  [ "$status" -eq 0 ]
  [[ "$(context)" == *"Keep the legacy outcome in scope."* ]]
}

@test "Codex-owned, malformed, and unknown project manifests defer" {
  publish_goal 'LIVE GOAL MUST NOT LEAK.'
  publish_manifest '{"schema_version":2,"squad":{"id":"portable.demo","name":"Demo"},"execution_mode":"one-time","destination":"project","providers":["claude","codex"],"runtime_owner":"codex","export_version":"1.1.0"}'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  publish_manifest '{not-json'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  publish_manifest '{"schema_version":99,"providers":["claude"],"runtime_owner":"claude"}'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "standalone plugin reminder uses only the vendored goal" {
  publish_goal 'LIVE GOAL MUST NOT LEAK.'
  publish_plugin_snapshot
  run_hook
  [ "$status" -eq 0 ]
  [[ "$(context)" == *"Use the portable snapshot only."* ]]
  [[ "$(context)" != *"LIVE GOAL MUST NOT LEAK"* ]]
}

@test "standalone plugin with missing or unavailable context defers" {
  publish_goal 'LIVE GOAL MUST NOT LEAK.'
  publish_plugin_snapshot
  rm "$PLUGIN_DIR/.squad/context/squad-goal.md"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf '%s\n' '{"schema_version":1,"squad_goal":{"source":".squad/goal.md","status":"missing","snapshot":null},"role_goals":[]}' \
    > "$PLUGIN_DIR/.squad/context/index.json"
  printf '%s\n' 'forged fallback' > "$PLUGIN_DIR/.squad/context/squad-goal.md"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing goal remains a silent no-op" {
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

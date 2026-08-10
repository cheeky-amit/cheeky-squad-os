#!/usr/bin/env bats
# Tests for skills/squad-env/scripts/provision.sh
#
# provision.sh materializes one sandbox per ACTIVE role that declares an
# `environment` block: workspace dir + scaffolded `dirs` + role-local bin/, a
# SOURCED env file, locally-copied context, and tool readiness. It runs only
# what it can contain; system/MCP/fetch needs are reported as global_needs and
# never executed. With --install it also runs kind:"local" installs inside the
# sandbox. These tests cover materialization, the dry-vs-install split, the
# contain-vs-propose classification, unsafe-workspace refusal, and preflight.

setup() {
  PROVISION="$BATS_TEST_DIRNAME/../skills/squad-env/scripts/provision.sh"
  REPO="$(mktemp -d)"
  cd "$REPO"
  mkdir -p .squad
  printf -- '---\nmode: one-time\n---\n' > .squad/goal.md
  echo "reference material" > ref.txt
  cat > .squad/roster.json <<'JSON'
{ "roles": [
    { "name": "puller", "active": true,
      "file_scope": ["out/**", ".squad/workspaces/puller/**"],
      "environment": {
        "workspace": ".squad/workspaces/puller/",
        "dirs": ["inputs", "outputs"],
        "env": { "OUT_DIR": "outputs" },
        "context": [ { "from": "ref.txt", "into": "inputs", "kind": "copy" } ],
        "tools": [
          { "name": "bash",       "kind": "system", "verify": "command -v bash" },
          { "name": "missingsys", "kind": "system", "verify": "command -v missingsys-xyz-123" },
          { "name": "localtool",  "kind": "local",  "install": "touch localtool-marker", "verify": "test -f localtool-marker" }
        ]
      }
    },
    { "name": "noenv",    "active": true,  "file_scope": ["x/**"] },
    { "name": "inactive", "active": false, "file_scope": ["y/**"],
      "environment": { "workspace": ".squad/workspaces/inactive/" } }
] }
JSON
}

teardown() {
  cd /
  rm -rf "$REPO"
}

# --- materialization (dry) ---------------------------------------------------

@test "materializes a sandbox only for ACTIVE roles with an environment" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"role":"puller"'* ]]
  [[ "$output" == *'"status":"provisioned"'* ]]
  [[ "$output" != *'"role":"noenv"'* ]]      # no environment block → skipped
  [[ "$output" != *'"role":"inactive"'* ]]   # inactive → skipped
  [ -d .squad/workspaces/puller ]
  [ -d .squad/workspaces/puller/bin ]
  [ -d .squad/workspaces/puller/inputs ]
  [ -d .squad/workspaces/puller/outputs ]
  [ ! -d .squad/workspaces/inactive ]
}

@test "writes a SOURCED env file with PATH + vars (never exported globally)" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [ -f .squad/workspaces/puller/env ]
  run cat .squad/workspaces/puller/env
  [[ "$output" == *"SOURCE"* ]]            # the usage comment flags it as sourced
  [[ "$output" == *"PATH="* ]]
  [[ "$output" == *"/bin:"* ]]             # role-local bin/ prepended
  [[ "$output" == *"OUT_DIR=outputs"* ]]
}

@test "seeds local context by copying into the sandbox" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [ -f .squad/workspaces/puller/inputs/ref.txt ]
}

@test "writes a receipt" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [ -f .squad/workspaces/puller/.provisioned.json ]
}

# --- contain-vs-propose classification --------------------------------------

@test "missing system tool is reported as a global_need, never installed" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"global_needs"'* ]]
  [[ "$output" == *"missingsys"* ]]
}

@test "missing local tool is listed in local_plan but NOT installed on a dry run" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"local_plan"'* ]]
  [[ "$output" == *"localtool"* ]]
  [ ! -f .squad/workspaces/puller/localtool-marker ]
}

@test "--install runs the local install inside the sandbox" {
  run "$PROVISION" --install
  [ "$status" -eq 0 ]
  [ -f .squad/workspaces/puller/localtool-marker ]
  [[ "$output" == *'"tools_installed":1'* ]]
}

@test "present tool verifies as ready" {
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"tools_ready":1'* ]]   # bash present; missingsys + localtool miss
}

# --- idempotency -------------------------------------------------------------

@test "second run is idempotent" {
  run "$PROVISION"; [ "$status" -eq 0 ]
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"provisioned"'* ]]
}

@test "canonical v2 environment maps directories, context, and non-secret variable values" {
  cat > .squad/roster.json <<'JSON'
{
  "schema_version": 2,
  "squad_goal_ref": ".squad/goal.md",
  "execution_mode": "one-time",
  "roles": [
    {
      "id": "v2-puller",
      "purpose": "Prepare v2 inputs",
      "description": "Use when v2 inputs need preparation",
      "file_ownership": {
        "include": ["out/**", ".squad/workspaces/v2-puller/**"],
        "exclude": []
      },
      "capabilities": ["filesystem.read", "shell.execute"],
      "reasoning": {"profile": "balanced", "effort": "inherit"},
      "active": true,
      "goal_ref": ".squad/role-goal-v2-puller.md",
      "environment": {
        "workspace": ".squad/workspaces/v2-puller/",
        "directories": ["inputs", "outputs"],
        "variables": {
          "OUTPUT_FORMAT": "portable json",
          "REPORT_LOCALE": "en_US.UTF-8"
        },
        "context": [
          {"source": "ref.txt", "target": "inputs", "kind": "copy"}
        ],
        "tools": [
          {"name": "bash", "kind": "system", "verify": "command -v bash"}
        ]
      },
      "provider_overrides": {
        "claude": {
          "model": "sonnet",
          "tools": ["Read", "Bash"],
          "agent_file": ".claude/agents/v2-puller.md"
        }
      }
    }
  ]
}
JSON

  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"role":"v2-puller"'* ]]
  [ -d .squad/workspaces/v2-puller/inputs ]
  [ -d .squad/workspaces/v2-puller/outputs ]
  [ -f .squad/workspaces/v2-puller/inputs/ref.txt ]
  run bash -c \
    '. .squad/workspaces/v2-puller/env && test "$OUTPUT_FORMAT" = "portable json" && test "$REPORT_LOCALE" = en_US.UTF-8'
  [ "$status" -eq 0 ]
}

@test "canonical v2 rejects unsafe environment variable names" {
  cat > .squad/roster.json <<'JSON'
{
  "schema_version": 2,
  "squad_goal_ref": ".squad/goal.md",
  "execution_mode": "one-time",
  "roles": [
    {
      "id": "bad-variable",
      "purpose": "Exercise variable validation",
      "description": "Use when variable validation is tested",
      "file_ownership": {"include": ["out/**"], "exclude": []},
      "capabilities": ["filesystem.read"],
      "reasoning": {"profile": "balanced", "effort": "inherit"},
      "active": true,
      "environment": {
        "workspace": ".squad/workspaces/bad-variable/",
        "directories": [],
        "variables": {"BAD-NAME": "ignored"},
        "context": [],
        "tools": []
      }
    }
  ]
}
JSON

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid environment variable name 'BAD-NAME'"* ]]
  ! grep -F 'BAD-NAME' .squad/workspaces/bad-variable/env
}

# --- safety ------------------------------------------------------------------

@test "skips and reports an unsafe absolute workspace (errors, exit 1)" {
  cat > .squad/roster.json <<'JSON'
{ "roles": [
    { "name": "bad", "active": true, "file_scope": ["**"],
      "environment": { "workspace": "/etc/evil" } }
] }
JSON
  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe"* ]]
  [ ! -d /etc/evil ]
}

@test "skips and reports a '..' traversal workspace" {
  cat > .squad/roster.json <<'JSON'
{ "roles": [
    { "name": "bad", "active": true, "file_scope": ["**"],
      "environment": { "workspace": "../escape" } }
] }
JSON
  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe"* ]]
  [ ! -d ../escape ]
}

@test "rejects an absolute local context source without reading it" {
  outside="$(mktemp -d)"
  printf '%s\n' 'outside-secret' > "$outside/secret.txt"
  jq --arg source "$outside/secret.txt" \
    '.roles[0].environment.context[0].from = $source' \
    .squad/roster.json > .squad/roster.next
  mv .squad/roster.next .squad/roster.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe or symlinked context source"* ]]
  [ ! -e .squad/workspaces/puller/inputs/secret.txt ]
  [ "$(<"$outside/secret.txt")" = "outside-secret" ]
  rm -rf "$outside"
}

@test "rejects traversal in a local context source without reading outside" {
  outside="$(mktemp)"
  printf '%s\n' 'outside-secret' > "$outside"
  source_path="../${outside##*/}"
  jq --arg source "$source_path" \
    '.roles[0].environment.context[0].from = $source' \
    .squad/roster.json > .squad/roster.next
  mv .squad/roster.next .squad/roster.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe or symlinked context source '$source_path'"* ]]
  [ ! -e ".squad/workspaces/puller/inputs/${outside##*/}" ]
  [ "$(<"$outside")" = "outside-secret" ]
  rm -f "$outside"
}

@test "rejects an option-shaped local context source" {
  jq '.roles[0].environment.context[0].from = "-R"' \
    .squad/roster.json > .squad/roster.next
  mv .squad/roster.next .squad/roster.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe or symlinked context source '-R'"* ]]
  [ ! -e .squad/workspaces/puller/inputs/-R ]
}

@test "rejects a globbed local context source instead of expanding it" {
  printf '%s\n' 'second reference' > ref-two.txt
  jq '.roles[0].environment.context[0].from = "ref*.txt"' \
    .squad/roster.json > .squad/roster.next
  mv .squad/roster.next .squad/roster.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe or symlinked context source 'ref*.txt'"* ]]
  [ ! -e .squad/workspaces/puller/inputs/ref.txt ]
  [ ! -e .squad/workspaces/puller/inputs/ref-two.txt ]
}

@test "rejects a symlinked local context source without reading outside" {
  outside="$(mktemp -d)"
  printf '%s\n' 'outside-secret' > "$outside/secret.txt"
  ln -s "$outside/secret.txt" linked-ref.txt
  jq '.roles[0].environment.context[0].from = "linked-ref.txt"' \
    .squad/roster.json > .squad/roster.next
  mv .squad/roster.next .squad/roster.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe or symlinked context source 'linked-ref.txt'"* ]]
  [ ! -e .squad/workspaces/puller/inputs/linked-ref.txt ]
  [ "$(<"$outside/secret.txt")" = "outside-secret" ]
  rm -rf "$outside"
}

@test "refuses a workspace symlink before writing outside the project" {
  outside="$(mktemp -d)"
  rm -rf .squad/workspaces
  ln -s "$outside" .squad/workspaces

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink component in environment.workspace"* ]]
  [ ! -e "$outside/puller" ]
  rm -rf "$outside"
}

@test "refuses a symlinked env file without sourcing or overwriting it" {
  mkdir -p .squad/workspaces/puller
  outside="$(mktemp -d)"
  printf '%s\n' 'user-owned-env' > "$outside/env"
  ln -s "$outside/env" .squad/workspaces/puller/env

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing symlinked environment file"* ]]
  [ "$(<"$outside/env")" = "user-owned-env" ]
  rm -rf "$outside"
}

@test "refuses a symlinked receipt without overwriting its target" {
  mkdir -p .squad/workspaces/puller
  outside="$(mktemp -d)"
  printf '%s\n' 'user-owned-receipt' > "$outside/receipt"
  ln -s "$outside/receipt" .squad/workspaces/puller/.provisioned.json

  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing symlinked provision receipt"* ]]
  [ "$(<"$outside/receipt")" = "user-owned-receipt" ]
  rm -rf "$outside"
}

# --- empty / preflight -------------------------------------------------------

@test "no roles with an environment → summary reports zero" {
  cat > .squad/roster.json <<'JSON'
{ "roles": [ { "name": "noenv", "active": true, "file_scope": ["x/**"] } ] }
JSON
  run "$PROVISION"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"roles":0'* ]]
}

@test "refuses when goal is missing" {
  rm -f .squad/goal.md
  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no squad goal"* ]]
}

@test "refuses when roster is missing" {
  rm -f .squad/roster.json
  run "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no roster"* ]]
}

@test "refuses when jq is missing (preflight, before any provisioning)" {
  bindir="$(mktemp -d)"
  ln -s "$(command -v bash)" "$bindir/bash"
  run env -i PATH="$bindir" bash "$PROVISION" "$REPO/.squad/roster.json" "$REPO/.squad/goal.md"
  rm -rf "$bindir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

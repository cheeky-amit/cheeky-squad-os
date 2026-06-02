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

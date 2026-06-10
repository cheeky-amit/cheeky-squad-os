#!/usr/bin/env bats
# Table-driven tests for skills/squad-verify/scripts/verify.sh
#
# The script is the READ-ONLY evidence scaffold behind the squad-verify skill:
# it extracts Definition-of-done bullets from goal.md (skipping frontmatter and
# HTML comments), counts deliverable files under each active role's file_scope,
# checks role-goal presence, and emits one JSON object per line. It never
# judges PASS/FAIL (every signal is "unverified") and never writes files.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../skills/squad-verify/scripts/verify.sh"
  PROJECT_DIR="$(mktemp -d)"
  mkdir -p "$PROJECT_DIR/.squad"
}

teardown() {
  rm -rf "$PROJECT_DIR"
}

# write_goal <dod-section-text> — goal.md with frontmatter + the given DoD body.
write_goal() {
  cat > "$PROJECT_DIR/.squad/goal.md" <<EOF
---
mode: one-time
created: 2026-06-09T00:00:00Z
target: 2026-06-16T00:00:00Z
---

# Squad goal

Deliver the ranked fix list within one week.

$1

## Out of scope

- iOS app
EOF
}

# default_roster — one active role "auditor" owning reports/**.
default_roster() {
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "one-time",
  "created": "2026-06-09T00:00:00Z",
  "roles": [
    { "name": "auditor", "purpose": "audit", "agent_file": ".claude/agents/auditor.md",
      "role_goal": ".squad/role-goal-auditor.md", "file_scope": ["reports/**"],
      "tools": ["Read"], "model": "sonnet", "active": true, "created": "2026-06-09T00:00:00Z" }
  ]
}
JSON
}

THREE_SIGNALS='## Definition of done

- All 8 findings have a documented owner
- Report exists at reports/report.md
- Lighthouse Performance score >= 90'

run_verify() {
  run bash -c "cd '$PROJECT_DIR' && bash '$SCRIPT'"
}

# --- preflight ----------------------------------------------------------------

@test "missing jq exits 1 and names jq on stderr" {
  bindir="$(mktemp -d)"
  ln -s "$(command -v bash)" "$bindir/bash"
  run env -i PATH="$bindir" bash "$SCRIPT"
  rm -rf "$bindir"
  [ "$status" -eq 1 ]
  [[ "$output" == *jq* ]]
}

@test "missing goal.md exits 1 and points at squad-onboard" {
  default_roster
  run_verify
  [ "$status" -eq 1 ]
  [[ "$output" == *squad-onboard* ]]
}

@test "missing roster.json exits 1 and points at squad-role" {
  write_goal "$THREE_SIGNALS"
  run_verify
  [ "$status" -eq 1 ]
  [[ "$output" == *squad-role* ]]
}

@test "invalid roster JSON exits 1" {
  write_goal "$THREE_SIGNALS"
  printf 'not json' > "$PROJECT_DIR/.squad/roster.json"
  run_verify
  [ "$status" -eq 1 ]
}

# --- signal extraction ----------------------------------------------------------

@test "three DoD bullets emit exactly three unverified signal lines" {
  write_goal "$THREE_SIGNALS"
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  [ "$(grep -c '"signal"' <<< "$output")" -eq 3 ]
  [ "$(grep -c '"status":"unverified"' <<< "$output")" -eq 3 ]
}

@test "HTML comment block inside the DoD section is not emitted as signals" {
  write_goal '## Definition of done

<!--
  3-5 observable signals that are TRUE when the squad has succeeded.
  Each must be checkable without judgement calls.

  Good signals:
    - "Lighthouse Performance score >= 90 on mobile"
    - "All 8 audit findings have a documented owner and ETA"

  Bad signals (too vague):
    - "site is fast"
-->

- Real signal one
- Real signal two <!-- inline comment stripped -->'
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  [ "$(grep -c '"signal"' <<< "$output")" -eq 2 ]
  [[ "$output" != *"site is fast"* ]]
  [[ "$output" != *"inline comment"* ]]
  [[ "$output" == *'"signal":"Real signal two"'* ]]
}

@test "frontmatter lines are never parsed as signals" {
  cat > "$PROJECT_DIR/.squad/goal.md" <<'EOF'
---
mode: one-time
created: 2026-06-09T00:00:00Z
target: 2026-06-16T00:00:00Z
tags:
- sneaky frontmatter bullet
---

# Squad goal

Outcome paragraph.

## Definition of done

- Only real signal
EOF
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  [ "$(grep -c '"signal"' <<< "$output")" -eq 1 ]
  [[ "$output" != *sneaky* ]]
}

@test "goal with no DoD section yields 0 signals but still exits 0" {
  write_goal '## Notes

- not a definition of done bullet'
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  [ "$(grep -c '"signal"' <<< "$output" || true)" -eq 0 ]
  [[ "$output" == *'"signals":0'* ]]
}

# --- role deliverables ----------------------------------------------------------

@test "inactive roles are skipped entirely" {
  write_goal "$THREE_SIGNALS"
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{ "roles": [ { "name": "ghost", "role_goal": ".squad/role-goal-ghost.md",
  "file_scope": ["x/**"], "active": false } ] }
JSON
  run_verify
  [ "$status" -eq 0 ]
  [ "$(grep -c '"role"' <<< "$output" || true)" -eq 0 ]
  [[ "$output" == *'"roles":0'* ]]
}

@test "files under the role's /** scope are counted" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/reports/sub"
  touch "$PROJECT_DIR/reports/report.md" "$PROJECT_DIR/reports/sub/data.json"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se '[.[] | select(.role == "auditor")][0].files_found == 2'
}

@test "empty or missing scope dir yields files_found 0 and exit 0" {
  write_goal "$THREE_SIGNALS"
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se '[.[] | select(.role == "auditor")][0].files_found == 0'
}

@test "non-recursive glob counts matching files without crossing directories" {
  write_goal "$THREE_SIGNALS"
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{ "roles": [ { "name": "rootdoc", "role_goal": ".squad/role-goal-rootdoc.md",
  "file_scope": ["*.md"], "active": true } ] }
JSON
  mkdir -p "$PROJECT_DIR/nested"
  touch "$PROJECT_DIR/top.md" "$PROJECT_DIR/nested/deep.md"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se '[.[] | select(.role == "rootdoc")][0].files_found == 1'
}

@test "role_goal_present reflects the role-goal file on disk" {
  write_goal "$THREE_SIGNALS"
  default_roster
  run_verify
  printf '%s\n' "$output" | jq -se '[.[] | select(.role == "auditor")][0].role_goal_present == false'
  printf 'slice' > "$PROJECT_DIR/.squad/role-goal-auditor.md"
  run_verify
  printf '%s\n' "$output" | jq -se '[.[] | select(.role == "auditor")][0].role_goal_present == true'
}

# --- output contract -------------------------------------------------------------

@test "summary line carries correct counts and every line is valid JSON" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/reports"
  touch "$PROJECT_DIR/reports/report.md"
  run_verify
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null
  done <<< "$output"
  printf '%s\n' "$output" | tail -n 1 \
    | jq -e '.summary == true and .roles == 1 and .signals == 3 and .errors == 0'
}

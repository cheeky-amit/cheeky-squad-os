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

# write_role_plan <role> <status-line> <extra-frontmatter-role-line> <deliverables> <assumptions>
# — writes .squad/role-plan-<role>.md. Kept as discrete args (not one big
# heredoc per test) so each test only varies the one thing it's testing.
write_role_plan() {
  local role="$1" status="$2" fm_role="$3" deliverables="$4" assumptions="$5"
  cat > "$PROJECT_DIR/.squad/role-plan-$role.md" <<EOF
---
role: $fm_role
created: 2026-06-09T00:00:00Z
status: $status
---

# Engagement record — $role

## Task read

Read the task.

## Intended approach

1. Do the thing.

## Deliverables

$deliverables

## Assumptions

$assumptions

## Amendments
EOF
}

# write_role_plan_escalated <role> <fm-role> <fired> <what-happened> <state-of-work> <what-would-unblock>
# — writes .squad/role-plan-<role>.md with status: escalated, the frontmatter
# "fired:" value, and the three "escalated only" hand-back sections. Each of
# the three body args may be empty to test a missing/blank section.
write_role_plan_escalated() {
  local role="$1" fm_role="$2" fired="$3" wh="$4" sw="$5" wu="$6"
  cat > "$PROJECT_DIR/.squad/role-plan-$role.md" <<EOF
---
role: $fm_role
created: 2026-06-09T00:00:00Z
status: escalated
fired: "$fired"
---

# Engagement record — $role

## Task read

Read the task.

## Intended approach

1. Do the thing.

## Deliverables

## Assumptions

## Amendments

## What happened

$wh

## State of the work

$sw

## What would unblock

$wu
EOF
}

# write_verification <resolved-escalations-body> — .squad/verification.md
# with a normal frontmatter shape plus, when non-empty, a
# "resolved_escalations:" YAML list built from the given body (one
# "- <role>" line per arg line). Pass "" for no resolved_escalations key at
# all (the missing-key case, distinct from "missing file" and "malformed").
write_verification() {
  local resolved="$1"
  {
    printf -- '---\n'
    printf 'verdict: partial\n'
    printf 'verified_at: 2026-06-10T00:00:00Z\n'
    printf 'goal_mode: one-time\n'
    printf 'signals_pass: 1\n'
    printf 'signals_fail: 0\n'
    printf 'signals_human: 0\n'
    if [ -n "$resolved" ]; then
      printf 'resolved_escalations:\n'
      printf '%s\n' "$resolved"
    fi
    printf -- '---\n'
    printf '\n# Squad verification\n'
  } > "$PROJECT_DIR/.squad/verification.md"
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

# default_roster_two_roles — two active roles, "auditor" (reports/**) and
# "scout" (findings/**), for escalation tests that need more than one role.
default_roster_two_roles() {
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "one-time",
  "created": "2026-06-09T00:00:00Z",
  "roles": [
    { "name": "auditor", "purpose": "audit", "agent_file": ".claude/agents/auditor.md",
      "role_goal": ".squad/role-goal-auditor.md", "file_scope": ["reports/**"],
      "tools": ["Read"], "model": "sonnet", "active": true, "created": "2026-06-09T00:00:00Z" },
    { "name": "scout", "purpose": "scout", "agent_file": ".claude/agents/scout.md",
      "role_goal": ".squad/role-goal-scout.md", "file_scope": ["findings/**"],
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

# --- engagement record (hard rule #11) -------------------------------------------

@test "no engagement record: role line is byte-identical to the pre-#11 shape" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/reports"
  touch "$PROJECT_DIR/reports/report.md"
  run_verify
  [ "$status" -eq 0 ]
  ROLE_LINE=$(printf '%s\n' "$output" | grep '"role":"auditor"')
  EXPECTED='{"role":"auditor","scope":["reports/**"],"files_found":1,"role_goal_present":false}'
  [ "$ROLE_LINE" = "$EXPECTED" ]
}

@test "engagement record present: role_plan_present and status are surfaced" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" \
    '- `reports/report.md`' \
    ''
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0] | .role_plan_present == true and .role_plan_status == "active"'
}

@test "amended status is read verbatim from frontmatter" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "amended" "auditor" '' ''
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_status == "amended"'
}

@test "frontmatter role mismatch: filename wins and the error counter increments" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "some-other-role" '' ''
  run_verify
  [ "$status" -eq 0 ]
  # still reported under the filename's role, "auditor" — never the frontmatter's
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")] | length == 1
     and .[0].role_plan_frontmatter_role_match == false'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.errors == 1'
}

@test "matching frontmatter role does not touch the error counter" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" '' ''
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_frontmatter_role_match == true'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.errors == 0'
}

@test "assumptions are counted per evidence grade" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" '' \
'- [confirmed] a — evidence: `x`
- [reported] b — source: goal
- [reported] c — source: human
- [inferred] d — reasoning: y
- [assumed] e — if wrong → reports/report.md'
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_assumption_grades
       == {confirmed: 1, reported: 2, inferred: 1, assumed: 1}'
}

@test "declared deliverables missing from disk are counted, present ones are not" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/reports"
  touch "$PROJECT_DIR/reports/report.md"
  write_role_plan "auditor" "active" "auditor" \
'- `reports/report.md`
- `reports/absent.md`
- `reports/also-absent.md`' \
    ''
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_deliverables_missing == 2'
}

@test "the if-wrong clause is extracted from each [assumed] bullet" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" '' \
'- [assumed] no other role writes reports/ — if wrong → reports/report.md
- [assumed] no clause on this one
- [assumed] ascii arrow variant — if wrong -> Report exists at reports/report.md'
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_assumed_risks
       == ["reports/report.md", "Report exists at reports/report.md"]'
}

@test ".squad/ files never inflate files_found, even under a ** scope" {
  write_goal "$THREE_SIGNALS"
  cat > "$PROJECT_DIR/.squad/roster.json" <<'JSON'
{ "roles": [ { "name": "auditor", "role_goal": ".squad/role-goal-auditor.md",
  "file_scope": ["**"], "active": true } ] }
JSON
  write_role_plan "auditor" "active" "auditor" '' ''
  touch "$PROJECT_DIR/top.md"
  run_verify
  [ "$status" -eq 0 ]
  # top.md counts; goal.md, roster.json, and the role-plan file itself do not.
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].files_found == 1'
}

@test "every emitted line, including the new engagement-record fields, is valid JSON" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" \
'- `reports/report.md`' \
'- [confirmed] a — evidence: `x`
- [assumed] b — if wrong → reports/report.md'
  run_verify
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null
  done <<< "$output"
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0]
       | (.role_plan_assumption_grades | type) == "object"
         and (.role_plan_assumed_risks | type) == "array"
         and (.role_plan_deliverables_missing | type) == "number"'
}

# --- escalation & the evidence bar (hard rules #14-#15) --------------------------
#
# THE LOAD-BEARING INVARIANT: a role can never mint the human's ruling.
# escalations_open = |records with status: escalated| minus |their roles
# named in verification.md's resolved_escalations| — the human's ruling is
# read only from .squad/verification.md, never from anything a role wrote.

@test "escalated record is detected: status surfaces and it counts toward escalations_open" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "3 consecutive 500s from the API" \
    "hit the rate limit on the 4th call" "partial: report skeleton only" \
    "a working API token"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_status == "escalated"'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 1'
}

@test "fired is extracted verbatim from frontmatter" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "budget exceeded after 3 retries" \
    "x" "y" "z"
  run_verify
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_fired
       == "budget exceeded after 3 retries"'
}

@test "resolved subtraction also works with flow-style resolved_escalations (the template's own placeholder shape)" {
  write_goal "$THREE_SIGNALS"
  default_roster_two_roles
  write_role_plan_escalated "auditor" "auditor" "fired A" "wh" "sw" "wu"
  write_role_plan_escalated "scout" "scout" "fired B" "wh" "sw" "wu"
  cat > "$PROJECT_DIR/.squad/verification.md" <<'EOF'
---
verdict: partial
verified_at: 2026-06-10T00:00:00Z
goal_mode: one-time
signals_pass: 1
signals_fail: 0
signals_human: 0
resolved_escalations: [auditor]
---

# Squad verification
EOF
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 1'
}

@test "resolved subtraction works with INDENTED block-style resolved_escalations (the canonical YAML spelling)" {
  # Regression: the parser originally required the dash at column 0, so the
  # two-space-indented list that templates/verification.md and
  # examples/klaviyo-audit.md both document was silently ignored — a ruling a
  # human had actually recorded never subtracted, and `met` stayed unreachable.
  write_goal "$THREE_SIGNALS"
  default_roster_two_roles
  write_role_plan_escalated "auditor" "auditor" "fired A" "wh" "sw" "wu"
  write_role_plan_escalated "scout" "scout" "fired B" "wh" "sw" "wu"
  cat > "$PROJECT_DIR/.squad/verification.md" <<'EOF'
---
verdict: partial
verified_at: 2026-06-10T00:00:00Z
goal_mode: one-time
escalations_open: 2
resolved_escalations:
  - auditor
  - "scout"
signals_pass: 1
---

# Squad verification
EOF
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 0'
}

@test "resolved subtraction: a resolved escalation drops out, an unresolved one stays open" {
  write_goal "$THREE_SIGNALS"
  default_roster_two_roles
  write_role_plan_escalated "auditor" "auditor" "fired A" "wh" "sw" "wu"
  write_role_plan_escalated "scout" "scout" "fired B" "wh" "sw" "wu"
  write_verification $'- auditor'
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 1'
}

@test "a resolved role that is no longer escalated does not go negative" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan "auditor" "active" "auditor" '' ''
  write_verification $'- auditor'
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 0'
}

@test "frontmatter role mismatch on an escalated record: filename wins for both the row and the open count" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "some-other-role" "fired text" "wh" "sw" "wu"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")] | length == 1
     and .[0].role_plan_frontmatter_role_match == false
     and .[0].role_plan_status == "escalated"'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.errors == 1 and .escalations_open == 1'
}

@test "missing verification.md: escalations_open is the full escalated count, not zero" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "fired text" "wh" "sw" "wu"
  run_verify
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT_DIR/.squad/verification.md" ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 1'
}

@test "malformed verification.md degrades to nothing-resolved without crashing" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "fired text" "wh" "sw" "wu"
  printf 'this is not yaml at all\n{{{ broken \x00 junk\nno frontmatter fence here\n' \
    > "$PROJECT_DIR/.squad/verification.md"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.escalations_open == 1'
}

@test "absence: no engagement record anywhere emits no escalation fields at all" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/reports"
  touch "$PROJECT_DIR/reports/report.md"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '(has("escalations_open") | not)'
  ROLE_LINE=$(printf '%s\n' "$output" | grep '"role":"auditor"')
  [[ "$ROLE_LINE" != *role_plan_fired* ]]
  [[ "$ROLE_LINE" != *role_plan_hand_back_sections_present* ]]
}

@test "escalated record missing its hand-back sections is flagged" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "fired text" "" "" ""
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0].role_plan_hand_back_sections_present
       == {what_happened: false, state_of_work: false, what_would_unblock: false}'
}

@test "escalation fields, including a populated resolved_escalations file, stay valid JSON" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_role_plan_escalated "auditor" "auditor" "fired text" "wh text" "sw text" "wu text"
  write_verification $'- someone-else'
  run_verify
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null
  done <<< "$output"
  printf '%s\n' "$output" | jq -se \
    '[.[] | select(.role == "auditor")][0]
       | (.role_plan_fired | type) == "string"
         and (.role_plan_hand_back_sections_present | type) == "object"
         and (.role_plan_hand_back_sections_present.what_happened | type) == "boolean"'
  printf '%s\n' "$output" | tail -n 1 | jq -e '(.escalations_open | type) == "number" and .escalations_open == 1'
}

# --- The belief ledger (hard rule #13) — world_conflicts ------------------------
#
# verify.sh re-derives this count itself, from every .squad/world/claims-*.md,
# rather than shelling out to skills/squad-world/scripts/world.sh. That keeps
# the script self-contained but makes DRIFT the risk, so these tests assert the
# exact validity rule hard rule #13 states — and the absence contract, which is
# independent of escalations_open's.

# write_claims <owner> <body> — .squad/world/claims-<owner>.md
write_claims() {
  mkdir -p "$PROJECT_DIR/.squad/world"
  printf '%s\n' "$2" > "$PROJECT_DIR/.squad/world/claims-$1.md"
}

# live_belief <key> [claim] [observed] — one well-formed live belief block
live_belief() {
  printf '## Belief: %s\n\nClaim: %s\nSource: x\nGrade: confirmed\nObserved: %s\nStatus: live\n' \
    "$1" "${2:-A claim.}" "${3:-2026-07-01}"
}

@test "no .squad/world/ at all: world_conflicts is OMITTED, not 0" {
  write_goal "$THREE_SIGNALS"
  default_roster
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '(has("world_conflicts") | not)'
}

@test "empty .squad/world/ directory: world_conflicts is present as 0" {
  write_goal "$THREE_SIGNALS"
  default_roster
  mkdir -p "$PROJECT_DIR/.squad/world"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "world_conflicts is independent of escalations_open's absence condition" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(live_belief shared)"
  run_verify
  [ "$status" -eq 0 ]
  # No engagement record anywhere -> escalations_open omitted; world/ exists
  # -> world_conflicts present. One feature without the other.
  printf '%s\n' "$output" | tail -n 1 | jq -e \
    '(has("escalations_open") | not) and .world_conflicts == 1'
}

@test "two live blocks under one key from different owners count as one conflict" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief k1)
$(live_belief k2)"
  write_claims "scout" "$(live_belief k1)
$(live_belief k3)"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "one owner's two live blocks under one key are not a conflict with themselves" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief dup 'first.')
$(live_belief dup 'second.')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "a block missing a required field never counts toward world_conflicts" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(printf '## Belief: shared\n\nClaim: no source here.\nGrade: confirmed\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "an off-vocabulary grade never counts toward world_conflicts" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(printf '## Belief: shared\n\nClaim: c.\nSource: y\nGrade: 0.73\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

# --- The research grade ceiling, re-derived here as well as in world.sh -------
#
# These two scripts are INDEPENDENT re-derivations of the same number, which is
# only worth having if they agree. They did not: world.sh applied the per-owner
# ceiling to claims-research.md and verify.sh did not, so the same ledger read
# conflicts:0 from one script and world_conflicts:1 from the other — squad-verify
# sent the human to adjudicate a dispute squad-world would not show them,
# because one of its two claimants was a block the ceiling had already excluded.

@test "research: an inferred block never counts toward world_conflicts (the ceiling)" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "scout" "$(live_belief shared)"
  write_claims "research" "$(printf '## Belief: shared\n\nClaim: a synthesis wearing a finding.\nSource: reasoned from two other findings\nGrade: inferred\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "research: an assumed block never counts toward world_conflicts (the ceiling)" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "scout" "$(live_belief shared)"
  write_claims "research" "$(printf '## Belief: shared\n\nClaim: a guess.\nSource: none\nGrade: assumed\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "research: a reported block DOES count — the ceiling stops at inferred/assumed" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "scout" "$(live_belief shared)"
  write_claims "research" "$(printf '## Belief: shared\n\nClaim: a sourced finding.\nSource: https://example.com/spec\nGrade: reported\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "the ceiling is research-only: claims-user.md inferred still counts" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "scout" "$(live_belief shared)"
  write_claims "user" "$(printf '## Belief: shared\n\nClaim: the human own inference, which is their prerogative.\nSource: reasoned from three quarters of tickets\nGrade: inferred\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "the ceiling is research-only: an ordinary role's inferred block still counts" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "scout" "$(live_belief shared)"
  write_claims "analyst" "$(printf '## Belief: shared\n\nClaim: a role inference about its own work.\nSource: reasoned from the deploy timeline\nGrade: inferred\nObserved: 2026-07-02\nStatus: live\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "superseded and retired blocks never count toward world_conflicts" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(printf '## Belief: shared\n\nClaim: c.\nSource: y\nGrade: confirmed\nObserved: 2026-07-02\nStatus: superseded\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

# Order is load-bearing, and must match world.sh's: the duplicate-live-key
# filter runs over blocks that ALREADY passed field validation. Run the other
# way round, a malformed sibling suppressed its well-formed neighbour and the
# real cross-owner dispute went unreported.
@test "a malformed sibling block never hides a real cross-owner conflict" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief contested 'A says X.')
$(printf '## Belief: contested\n\nClaim: a botched second write.\nGrade: confirmed\nObserved: 2026-07-02\nStatus: live\n')"
  write_claims "scout" "$(live_belief contested 'B says Y.' 2026-07-03)"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "a required field under a later unrelated heading does not complete a block" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(printf '## Belief: shared\n\nClaim: c.\nSource: y\nGrade: confirmed\n\n## Notes\n\nObserved: 2026-07-02\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "a stray non-claims file under world/ is ignored, not parsed" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  mkdir -p "$PROJECT_DIR/.squad/world"
  printf '%s\n' "$(live_belief shared)" > "$PROJECT_DIR/.squad/world/README.md"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

@test "claims files never inflate files_found for a role scoped **" {
  write_goal "$THREE_SIGNALS"
  cat > "$PROJECT_DIR/.squad/roster.json" <<'EOF'
{"squad_goal_ref": ".squad/goal.md", "mode": "one-time",
 "roles": [{"name": "auditor", "purpose": "p", "agent_file": ".claude/agents/auditor.md",
            "role_goal": ".squad/role-goal-auditor.md", "file_scope": ["**"],
            "tools": ["Read"], "model": "sonnet", "active": true}]}
EOF
  write_claims "auditor" "$(live_belief shared)"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep '"role":"auditor"' | jq -e '.files_found == 0'
}

@test "world_conflicts: a template-annotated Status line does not hide a conflict" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(printf '## Belief: shared\n\nClaim: A says X.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live   <!-- live | superseded | retired -->\n')"
  write_claims "scout" "$(live_belief shared)"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 1'
}

@test "world_conflicts: an off-vocabulary Status is excluded like any invalid block" {
  write_goal "$THREE_SIGNALS"
  default_roster
  write_claims "auditor" "$(live_belief shared)"
  write_claims "scout" "$(printf '## Belief: shared\n\nClaim: c.\nSource: y\nGrade: confirmed\nObserved: 2026-07-02\nStatus: activ\n')"
  run_verify
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.world_conflicts == 0'
}

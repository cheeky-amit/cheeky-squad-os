#!/usr/bin/env bats
# Table-driven tests for hooks/session-start.sh
#
# The hook injects the squad goal (unchanged behavior) and, since hard rules
# #14/#15, an open-escalation notice appended AFTER the goal:
#   goal injected · no-goal nudge unchanged · one open escalation notified ·
#   escalation resolved via resolved_escalations not notified · multiple
#   escalations counted · status: active not counted · malformed
#   verification.md degrades safely · no .squad/ at all · exit 0 on every
#   path · byte-identical output when nothing is escalated.
#
# THE LOAD-BEARING INVARIANT is exercised indirectly here: "resolved" is
# recognized ONLY via .squad/verification.md's frontmatter
# resolved_escalations: list, never via anything on the role-plan record
# itself (there is no `resolved` status, no `resolution:` field — a role
# has nothing in its own file it could flip to silence this notice).
#
# Since hard rule #12, the hook also appends the partner model
# (.squad/partner.md) immediately after the goal:
#   goal-only behavior unchanged when no partner.md exists · partner
#   appended after the goal, in the documented order relative to the
#   escalation notice · appended even with no squad goal set (the file
#   describes the human, not the squad) · empty partner.md ([ -s ] gate)
#   changes nothing, byte-identical · absent partner.md is byte-identical
#   to a build with no partner-model support · exit 0 even when
#   partner.md is unreadable.

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/session-start.sh"
  PROJECT_DIR="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
}

teardown() {
  rm -rf "$PROJECT_DIR"
}

# run_hook → invoke the hook with an empty stdin payload (SessionStart's
# input carries no fields this hook reads); $output captures stdout+stderr.
run_hook() {
  run bash -c "printf '{}' | '$HOOK'"
}

# ctx → the decoded additionalContext string from the last $output.
ctx() {
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext'
}

publish_goal() {
  mkdir -p "$PROJECT_DIR/.squad"
  printf '%s\n' "$1" > "$PROJECT_DIR/.squad/goal.md"
}

# publish_partner <content> → writes .squad/partner.md with the given
# content (non-empty by construction, since printf always adds a newline).
publish_partner() {
  mkdir -p "$PROJECT_DIR/.squad"
  printf '%s\n' "$1" > "$PROJECT_DIR/.squad/partner.md"
}

# publish_plan <role> <status> → an engagement record for <role> with the
# given frontmatter status (active | escalated | ...).
publish_plan() {
  mkdir -p "$PROJECT_DIR/.squad"
  printf -- '---\nrole: %s\ncreated: 2026-07-29T00:00:00Z\nstatus: %s\n---\n\n# Engagement record — %s\n' \
    "$1" "$2" "$1" > "$PROJECT_DIR/.squad/role-plan-$1.md"
}

# publish_verification <resolved-roles...> → verification.md whose
# frontmatter resolved_escalations: list names each given role.
publish_verification() {
  mkdir -p "$PROJECT_DIR/.squad"
  {
    printf -- '---\n'
    printf 'verdict: partial\n'
    printf 'resolved_escalations:\n'
    for r in "$@"; do
      printf '  - %s\n' "$r"
    done
    printf -- '---\n\n# Squad verification\n'
  } > "$PROJECT_DIR/.squad/verification.md"
}

# --- goal injection (unchanged) ------------------------------------------------

@test "goal is injected as before, unchanged by escalation logic" {
  publish_goal '# Goal

Ship the thing.'
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"[cheeky-squad-os squad goal in scope — every action must serve this outcome]"* ]]
  [[ "$out" == *"Ship the thing."* ]]
}

@test "no-goal nudge is unchanged when nothing is escalated" {
  run_hook
  [ "$status" -eq 0 ]
  [ "$(ctx)" = "no squad goal set — run /cheeky-squad-os:squad-onboard to set one" ]
}

# --- byte-identical absence contract -------------------------------------------

@test "no .squad/ at all: output identical to no-goal baseline" {
  # PROJECT_DIR has no .squad/ whatsoever — not even the directory.
  run_hook
  [ "$status" -eq 0 ]
  [ "$(ctx)" = "no squad goal set — run /cheeky-squad-os:squad-onboard to set one" ]
}

@test "output is byte-identical whether or not the escalation machinery ran, when nothing is escalated" {
  publish_goal 'Goal body.'
  run_hook
  baseline="$output"

  # Add role-plan records, none escalated, and a verification.md with no
  # resolved_escalations at all — must not change a single byte of output.
  publish_plan "alpha" "active"
  publish_plan "beta" "amended"
  {
    printf -- '---\nverdict: met\n---\n\n# Squad verification\n'
  } > "$PROJECT_DIR/.squad/verification.md"

  run_hook
  [ "$status" -eq 0 ]
  [ "$output" = "$baseline" ]
}

# --- open escalation notice ----------------------------------------------------

@test "one open escalation is notified, appended after the goal" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"Goal body."* ]]
  [[ "$out" == *"[cheeky-squad-os: 1 open escalation is waiting on your ruling — see .squad/verification.md]"* ]]
  # goal text precedes the notice
  goal_pos=$(printf '%s' "$out" | grep -bo "Goal body." | head -1 | cut -d: -f1)
  notice_pos=$(printf '%s' "$out" | grep -bo "cheeky-squad-os: 1 open escalation" | head -1 | cut -d: -f1)
  [ "$goal_pos" -lt "$notice_pos" ]
}

@test "escalation resolved via resolved_escalations is not notified" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  publish_verification "alpha"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" != *"open escalation"* ]]
}

@test "multiple open escalations are counted" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  publish_plan "beta" "escalated"
  publish_plan "gamma" "escalated"
  publish_verification "beta"   # only beta is resolved -> 2 remain open
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"[cheeky-squad-os: 2 open escalations are waiting on your ruling — see .squad/verification.md]"* ]]
}

@test "escalation resolved via flow-style resolved_escalations: [a, b] is also recognized" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  {
    printf -- '---\nverdict: partial\nresolved_escalations: [alpha, beta]\n---\n\n# Squad verification\n'
  } > "$PROJECT_DIR/.squad/verification.md"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" != *"open escalation"* ]]
}

@test "a record with status: active is not counted" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "active"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" != *"open escalation"* ]]
}

# --- degradation --------------------------------------------------------------

@test "malformed verification.md degrades safely (still notifies, still exits 0)" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  # No frontmatter fences at all — garbage content.
  printf 'this is not yaml at all\njust some prose\n' > "$PROJECT_DIR/.squad/verification.md"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"[cheeky-squad-os: 1 open escalation is waiting on your ruling — see .squad/verification.md]"* ]]
}

@test "exit 0 on every path, including a role-plan file that is unreadable" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  chmod 000 "$PROJECT_DIR/.squad/role-plan-alpha.md"
  run_hook
  [ "$status" -eq 0 ]
  chmod 644 "$PROJECT_DIR/.squad/role-plan-alpha.md"
}

@test "missing jq: escalation notice still surfaces, goal-content injection degrades with the loss named" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  bindir="$(mktemp -d)"
  for b in bash cat grep awk; do ln -s "$(command -v "$b")" "$bindir/$b"; done
  run env -i PATH="$bindir" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash -c "printf '{}' | '$HOOK'"
  rm -rf "$bindir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq not installed"* ]]
  [[ "$output" == *"full goal injection disabled"* ]]
  [[ "$output" == *"1 open escalation is waiting on your ruling"* ]]
}

# --- partner model (hard rule #12) ----------------------------------------------

@test "goal-only behavior is unchanged when no partner.md exists" {
  publish_goal 'Goal body.'
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"Goal body."* ]]
  [[ "$out" != *"partner model"* ]]
  [[ "$out" != *"partner.md"* ]]
}

@test "partner model is appended after the goal, when present and non-empty" {
  publish_goal 'Goal body.'
  publish_partner '# Partner model

## Decide vs. ask

Always ask first: anything customer-facing.'
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"Goal body."* ]]
  [[ "$out" == *"[cheeky-squad-os partner model in scope — .squad/partner.md, hard rule #12: told, not inferred]"* ]]
  [[ "$out" == *"Always ask first: anything customer-facing."* ]]
  goal_pos=$(printf '%s' "$out" | grep -bo "Goal body." | head -1 | cut -d: -f1)
  partner_pos=$(printf '%s' "$out" | grep -bo "Always ask first: anything customer-facing." | head -1 | cut -d: -f1)
  [ "$goal_pos" -lt "$partner_pos" ]
}

@test "partner model is appended even with no squad goal set" {
  publish_partner 'Partner content with no goal on file.'
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"no squad goal set"* ]]
  [[ "$out" == *"Partner content with no goal on file."* ]]
}

@test "partner model, escalation notice, and goal coexist in the documented order" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  publish_partner 'Standing constraint: never touch prod directly.'
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  goal_pos=$(printf '%s' "$out" | grep -bo "Goal body." | head -1 | cut -d: -f1)
  partner_pos=$(printf '%s' "$out" | grep -bo "Standing constraint" | head -1 | cut -d: -f1)
  notice_pos=$(printf '%s' "$out" | grep -bo "open escalation" | head -1 | cut -d: -f1)
  [ "$goal_pos" -lt "$partner_pos" ]
  [ "$partner_pos" -lt "$notice_pos" ]
}

@test "empty partner.md file ([ -s ] gate) changes nothing, byte-identical" {
  publish_goal 'Goal body.'
  run_hook
  baseline="$output"

  mkdir -p "$PROJECT_DIR/.squad"
  : > "$PROJECT_DIR/.squad/partner.md"   # zero bytes — exists but empty

  run_hook
  [ "$status" -eq 0 ]
  [ "$output" = "$baseline" ]
}

@test "absent partner.md is byte-identical to a build with no partner-model support" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  run_hook
  [ "$status" -eq 0 ]
  out="$(ctx)"
  [[ "$out" == *"Goal body."* ]]
  [[ "$out" == *"1 open escalation"* ]]
  [[ "$out" != *"partner"* ]]
}

@test "exit 0 even when partner.md is unreadable" {
  publish_goal 'Goal body.'
  publish_partner 'Some standing constraint.'
  chmod 000 "$PROJECT_DIR/.squad/partner.md"
  run_hook
  [ "$status" -eq 0 ]
  chmod 644 "$PROJECT_DIR/.squad/partner.md"
}

@test "missing jq: partner model degrades the same way goal content does (no crash, notice still fires)" {
  publish_goal 'Goal body.'
  publish_plan "alpha" "escalated"
  publish_partner 'Some standing constraint.'
  bindir="$(mktemp -d)"
  for b in bash cat grep awk; do ln -s "$(command -v "$b")" "$bindir/$b"; done
  run env -i PATH="$bindir" CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash -c "printf '{}' | '$HOOK'"
  rm -rf "$bindir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq not installed"* ]]
  [[ "$output" == *"1 open escalation is waiting on your ruling"* ]]
}

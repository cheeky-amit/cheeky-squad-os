#!/usr/bin/env bats
# Table-driven tests for skills/squad-world/scripts/world.sh
#
# The script is the READ-ONLY parser/validator behind hard rule #13 (the
# shared world model / belief ledger): it parses every
# .squad/world/claims-<owner>.md, validates each belief block (Claim,
# Source, Grade, Observed all required; Grade and Status on-vocabulary; no
# duplicate live key within one file, checked AFTER field validation),
# detects cross-owner conflicts on identically keyed live blocks, and either
# dumps JSON lines (default) or performs the --index projection itself as
# literal pasteable text. It never writes a file and never judges a
# conflict — only the human does.
#
# Several tests below exist because the behaviour they assert was once
# WRONG in a way that failed silently — a belief that neither projected nor
# reported. Those are marked in place; do not fold them into a general case.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../skills/squad-world/scripts/world.sh"
  PROJECT_DIR="$(mktemp -d)"
  mkdir -p "$PROJECT_DIR/.squad/world"
}

teardown() {
  rm -rf "$PROJECT_DIR"
}

# write_claims <owner> <heredoc-body> — writes .squad/world/claims-<owner>.md
write_claims() {
  local owner="$1"
  local body="$2"
  printf '%s\n' "$body" > "$PROJECT_DIR/.squad/world/claims-$owner.md"
}

# valid_block <key> [observed] — a single well-formed live belief block, so
# every "does X get excluded" test still has at least one belief that keeps
# the absence-contract guard from suppressing all output.
valid_block() {
  local key="$1" observed="${2:-2026-07-20}"
  printf '## Belief: %s\n\nClaim: A baseline claim.\nSource: `x`\nGrade: confirmed\nObserved: %s\nStatus: live\n' \
    "$key" "$observed"
}

run_world() {
  run bash -c "cd '$PROJECT_DIR' && bash '$SCRIPT' $*"
}

# --- absence contract -----------------------------------------------------------

@test "absent .squad/world/ emits nothing" {
  rm -rf "$PROJECT_DIR/.squad/world"
  run_world
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absent .squad/world/ emits nothing in --index mode either" {
  rm -rf "$PROJECT_DIR/.squad/world"
  run_world --index
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "world/ present but nothing parseable emits nothing" {
  write_claims "auditor" "$(printf 'Claim: no source here.\nGrade: confirmed\nObserved: 2026-07-01\n')"
  # not even a "## Belief:" heading — degrades to nothing parsed at all
  run_world
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The default mode is the HUMAN's inspection surface, so its silence
# condition is narrower than --index's. A ledger whose every block is
# invalid is exactly the case where going quiet would be worst: the beliefs
# vanish from every prompt and nothing says why.
@test "a ledger of only invalid blocks still reports them in default mode" {
  write_claims "auditor" "$(printf '## Belief: rumor\n\nClaim: c.\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"rumor"'* ]]
  [[ "$output" == *'"missing_source"'* ]]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.summary == true and .live == 0 and .invalid == 1'
}

@test "a ledger of only invalid blocks still projects nothing into a prompt" {
  write_claims "auditor" "$(printf '## Belief: rumor\n\nClaim: c.\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world --index
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- field validation (hard rule #13's teeth) ------------------------------------

@test "missing Source is invalid and excluded" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: no-source\n\nClaim: c.\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"no-source"'* ]]
  [[ "$output" == *'"missing_source"'* ]]
  [[ "$output" != *'"belief":"no-source"'* ]]
}

@test "missing Grade is invalid and excluded" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: no-grade\n\nClaim: c.\nSource: x\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"no-grade"'* ]]
  [[ "$output" == *'"missing_grade"'* ]]
  [[ "$output" != *'"belief":"no-grade"'* ]]
}

@test "missing Observed is invalid and excluded" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: no-observed\n\nClaim: c.\nSource: x\nGrade: confirmed\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"no-observed"'* ]]
  [[ "$output" == *'"missing_observed"'* ]]
  [[ "$output" != *'"belief":"no-observed"'* ]]
}

@test "missing Claim is invalid and excluded" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: no-claim\n\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"no-claim"'* ]]
  [[ "$output" == *'"missing_claim"'* ]]
  [[ "$output" != *'"belief":"no-claim"'* ]]
}

@test "off-vocabulary grade is invalid and excluded" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: bad-grade\n\nClaim: c.\nSource: x\nGrade: pretty-sure\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"bad-grade"'* ]]
  [[ "$output" == *'"bad_grade"'* ]]
  [[ "$output" != *'"belief":"bad-grade"'* ]]
}

@test "duplicate live key within one file: both blocks invalid, neither projects" {
  write_claims "auditor" "$(printf '## Belief: dup\n\nClaim: first.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n\n## Belief: dup\n\nClaim: second.\nSource: y\nGrade: assumed\nObserved: 2026-07-02\nStatus: live\n')
$(valid_block ok-key)"
  run_world
  [ "$status" -eq 0 ]
  [ "$(grep -c '"invalid":"dup"' <<< "$output")" -eq 2 ]
  [[ "$output" == *'"duplicate_live_key"'* ]]
  [[ "$output" != *'"belief":"dup"'* ]]
}

# Order is load-bearing: the duplicate check runs over blocks that already
# passed field validation. Run the other way round, a malformed sibling
# dragged its well-formed neighbour down — and, worse, hid the cross-owner
# conflict that neighbour was party to.
@test "a field-invalid sibling under the same key does not invalidate the good block" {
  write_claims "auditor" "$(printf '## Belief: shared\n\nClaim: well formed.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n\n## Belief: shared\n\nClaim: no source on this one.\nGrade: confirmed\nObserved: 2026-07-02\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"belief":"shared"'*'"claim":"well formed."'* ]]
  [[ "$output" != *'"duplicate_live_key"'* ]]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.live == 1 and .invalid == 1'
}

@test "a field-invalid sibling never hides a real cross-owner conflict" {
  write_claims "auditor" "$(printf '## Belief: contested\n\nClaim: A says X.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n\n## Belief: contested\n\nClaim: a botched second write.\nGrade: confirmed\nObserved: 2026-07-02\nStatus: live\n')"
  write_claims "scout" "$(printf '## Belief: contested\n\nClaim: B says Y.\nSource: y\nGrade: reported\nObserved: 2026-07-03\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"conflict":"contested"'* ]]
  printf '%s\n' "$output" | grep '"conflict":"contested"' | jq -e '.owners == ["auditor","scout"]'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.conflicts == 1'
}

# A belief block ends at the next markdown heading of ANY level. Without
# that, a required field sitting under an unrelated heading later in the
# file completed a block from outside itself — a rumor reaching a prompt
# through the side door.
@test "a required field under a later unrelated heading does not complete a block" {
  write_claims "auditor" "$(printf '## Belief: smuggled\n\nClaim: c.\nSource: x\nGrade: confirmed\n\n## Notes\n\nObserved: 2026-07-01\n')
$(valid_block ok-key)"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"smuggled"'* ]]
  [[ "$output" == *'"missing_observed"'* ]]
  [[ "$output" != *'"belief":"smuggled"'* ]]
  run_world --index
  [[ "$output" != *"smuggled"* ]]
}

@test "same key, one live one superseded, in the same file is NOT a duplicate" {
  write_claims "auditor" "$(printf '## Belief: evolves\n\nClaim: old.\nSource: x\nGrade: confirmed\nObserved: 2026-01-01\nStatus: superseded\n\n## Belief: evolves\n\nClaim: new.\nSource: y\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" != *'"invalid":"evolves"'* ]]
  [ "$(grep -c '"belief":"evolves"' <<< "$output")" -eq 2 ]
}

# --- superseded / retired lifecycle -----------------------------------------------

@test "superseded and retired blocks are parsed but never projected" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: old-one\n\nClaim: old.\nSource: x\nGrade: confirmed\nObserved: 2026-01-01\nStatus: superseded\n\n## Belief: retired-one\n\nClaim: retired.\nSource: y\nGrade: confirmed\nObserved: 2026-01-02\nStatus: retired\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"belief":"old-one"'*'"status":"superseded"'* ]]
  [[ "$output" == *'"belief":"retired-one"'*'"status":"retired"'* ]]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.live == 1'
  run_world --index
  [[ "$output" != *"old-one"* ]]
  [[ "$output" != *"retired-one"* ]]
}

# --- cross-file conflict detection ------------------------------------------------

@test "two live blocks under the same key from different owners is a conflict, not invalid" {
  write_claims "auditor" "$(printf '## Belief: shared-key\n\nClaim: A says X.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  write_claims "scout" "$(printf '## Belief: shared-key\n\nClaim: B says Y.\nSource: y\nGrade: reported\nObserved: 2026-07-05\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"conflict":"shared-key"'* ]]
  printf '%s\n' "$output" | grep '"conflict":"shared-key"' \
    | jq -e '.owners == ["auditor","scout"]'
  [[ "$output" != *'"invalid":"shared-key"'* ]]
  [ "$(grep -c '"belief":"shared-key"' <<< "$output")" -eq 2 ]
}

@test "one live claim under a key (only one owner) is never a conflict" {
  write_claims "auditor" "$(valid_block solo-key)"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" != *'"conflict"'* ]]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.conflicts == 0'
}

# --- --index projection -----------------------------------------------------------

@test "--index caps the undisputed index list and names the remainder" {
  BODY=""
  for i in 1 2 3 4 5; do
    BODY="$BODY
$(valid_block "key-$i" "2026-07-0$i")"
  done
  write_claims "auditor" "$BODY"
  run_world --index --cap 3
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- key-' <<< "$output")" -eq 3 ]
  [[ "$output" == *"+2 more on disk"* ]]
}

@test "--index disputed-cap limits full disputed blocks and names the remainder" {
  BODY_A=""
  BODY_B=""
  for i in 1 2 3; do
    BODY_A="$BODY_A
$(valid_block "dispute-$i" "2026-07-0$i")"
    BODY_B="$BODY_B
$(printf '## Belief: dispute-%s\n\nClaim: contradicts %s.\nSource: y\nGrade: reported\nObserved: 2026-07-1%s\nStatus: live\n' "$i" "$i" "$i")"
  done
  write_claims "auditor" "$BODY_A"
  write_claims "scout" "$BODY_B"
  run_world --index --disputed-cap 1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^### dispute-' <<< "$output")" -eq 1 ]
  [[ "$output" == *"+2 more disputed — run squad-world"* ]]
}

@test "--index prints the invalid count on its own line" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: broken\n\nClaim: c.\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n')"
  run_world --index
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n'"Invalid: 1 (excluded from every projection)"* ]] \
    || [[ "$output" == "Invalid: 1 (excluded from every projection)"* ]]
}

@test "--index orders undisputed beliefs by recency, newest first" {
  write_claims "auditor" "$(valid_block older 2026-01-01)
$(valid_block newest 2026-09-01)
$(valid_block middle 2026-05-01)"
  run_world --index
  [ "$status" -eq 0 ]
  ORDER=$(printf '%s\n' "$output" | grep -E '^- (older|newest|middle):' | sed -E 's/^- ([a-z]+):.*/\1/')
  [ "$ORDER" = "$(printf 'newest\nmiddle\nolder')" ]
}

@test "--index truncates a long line to exactly 80 bytes" {
  LONG_CLAIM=$(printf 'x%.0s' $(seq 1 200))
  write_claims "auditor" "$(printf '## Belief: long-one\n\nClaim: %s\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n' "$LONG_CLAIM")"
  run_world --index
  [ "$status" -eq 0 ]
  LINE=$(printf '%s\n' "$output" | grep '^- long-one:')
  [ "$(printf '%s' "$LINE" | wc -c | tr -d ' ')" -eq 80 ]
  [[ "$LINE" == *"..." ]]
}

# The cap is a BYTE cap so it is deterministic at every locale, and the cut
# must never land inside a multi-byte UTF-8 sequence — a half-character in a
# spawn prompt is worse than a shorter line.
@test "--index truncation never splits a UTF-8 character" {
  LONG_CLAIM="עברית עברית עברית עברית עברית עברית עברית עברית עברית עברית עברית"
  write_claims "auditor" "$(printf '## Belief: utf8-one\n\nClaim: %s\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n' "$LONG_CLAIM")"
  run_world --index
  [ "$status" -eq 0 ]
  LINE=$(printf '%s\n' "$output" | grep '^- utf8-one:')
  [ "$(printf '%s' "$LINE" | wc -c | tr -d ' ')" -le 80 ]
  [[ "$LINE" == *"..." ]]
  printf '%s' "$LINE" | iconv -f UTF-8 -t UTF-8 >/dev/null
}

# Same input, two locales, byte-identical output — otherwise the token
# budget is a hope rather than a bats-defensible claim.
@test "--index output does not depend on the runner's locale" {
  LONG_CLAIM=$(printf 'y%.0s' $(seq 1 200))
  write_claims "auditor" "$(printf '## Belief: locale-one\n\nClaim: %s\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live\n' "$LONG_CLAIM")"
  A=$(cd "$PROJECT_DIR" && LC_ALL=C bash "$SCRIPT" --index)
  B=$(cd "$PROJECT_DIR" && LC_ALL=en_US.UTF-8 bash "$SCRIPT" --index)
  [ "$A" = "$B" ]
}

@test "--index emits nothing but the empty string when the squad has no beliefs" {
  run_world --index
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- robustness ---------------------------------------------------------------

@test "malformed claims file degrades without crashing" {
  printf 'not a belief file at all\n\x00\x01 garbage bytes\n## Belief:\n\nClaim: no key text above\n' \
    > "$PROJECT_DIR/.squad/world/claims-auditor.md"
  write_claims "scout" "$(valid_block ok-key)"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"belief":"ok-key"'* ]]
}

@test "a claims file with an empty owner name (claims-.md) is skipped, not crashed" {
  printf 'garbage\n' > "$PROJECT_DIR/.squad/world/claims-.md"
  write_claims "scout" "$(valid_block ok-key)"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"belief":"ok-key"'* ]]
}

# --- output contract ------------------------------------------------------------

@test "every emitted line is valid JSON, and the summary line is always last" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: broken\n\nGrade: not-a-grade\nObserved: 2026-07-01\nStatus: live\n')"
  write_claims "scout" "$(printf '## Belief: ok-key\n\nClaim: a different owner, same key.\nSource: y\nGrade: reported\nObserved: 2026-07-02\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null
  done <<< "$output"
  printf '%s\n' "$output" | tail -n 1 | jq -e '.summary == true'
}

@test "summary line carries correct counts" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: broken\n\nGrade: not-a-grade\nObserved: 2026-07-01\nStatus: live\n')"
  write_claims "scout" "$(printf '## Belief: ok-key\n\nClaim: a different owner, same key.\nSource: y\nGrade: reported\nObserved: 2026-07-02\nStatus: live\n')"
  run_world
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | tail -n 1 | jq -e \
    '.files == 2 and .beliefs == 2 and .live == 2 and .invalid == 1 and .conflicts == 1'
}

# --- field-value hygiene ----------------------------------------------------------

# templates/world-claims.md annotates its own fields with inline HTML
# comments. A block copied from the template carried the comment into the
# VALUE, so the status read as "live <!-- … -->" — not "live". The belief
# then silently never projected and never showed as invalid either (no field
# was missing), taking any dispute it was party to down with it. That is the
# worst failure shape this feature has.
@test "a trailing HTML comment is stripped from a field value" {
  write_claims "auditor" "$(printf '## Belief: annotated\n\nClaim: c.  <!-- one sentence -->\nSource: x <!-- a file -->\nGrade: confirmed  <!-- one of four -->\nObserved: 2026-07-01 <!-- ISO-8601 -->\nStatus: live   <!-- live | superseded | retired -->\n')"
  run_world
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep '"belief":"annotated"' \
    | jq -e '.status == "live" and .grade == "confirmed" and .observed == "2026-07-01" and .claim == "c." and .source == "x"'
  printf '%s\n' "$output" | tail -n 1 | jq -e '.live == 1 and .invalid == 0'
}

@test "an annotated block still conflicts with another owner's, rather than vanishing" {
  write_claims "auditor" "$(printf '## Belief: shared\n\nClaim: A says X.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: live   <!-- live | superseded | retired -->\n')"
  write_claims "scout" "$(valid_block shared)"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"conflict":"shared"'* ]]
  printf '%s\n' "$output" | tail -n 1 | jq -e '.conflicts == 1'
}

@test "an off-vocabulary Status is reported invalid, not silently dropped" {
  write_claims "auditor" "$(valid_block ok-key)
$(printf '## Belief: typo-status\n\nClaim: c.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\nStatus: activ\n')"
  run_world
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invalid":"typo-status"'* ]]
  [[ "$output" == *'"bad_status"'* ]]
  [[ "$output" != *'"belief":"typo-status"'* ]]
}

@test "an absent Status still defaults to live" {
  write_claims "auditor" "$(printf '## Belief: no-status\n\nClaim: c.\nSource: x\nGrade: confirmed\nObserved: 2026-07-01\n')"
  run_world
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep '"belief":"no-status"' | jq -e '.status == "live"'
}

# The shipped template must survive being used as what it is a template for.
@test "the shipped world-claims template parses without a crash or a surprise" {
  cp "$BATS_TEST_DIRNAME/../templates/world-claims.md" \
     "$PROJECT_DIR/.squad/world/claims-auditor.md"
  run_world
  [ "$status" -eq 0 ]
  # The worked example is a real, valid, live belief...
  printf '%s\n' "$output" | grep '"belief":"checkout-p95-latency-exceeds-3s"' | jq -e '.status == "live"'
  # ...and the placeholder skeleton is correctly rejected, not half-accepted.
  [[ "$output" == *'"invalid":"<kebab-case-key>"'* ]]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null
  done <<< "$output"
}

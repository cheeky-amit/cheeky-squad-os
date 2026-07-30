#!/usr/bin/env bash
# session-start.sh — cheeky-squad-os SessionStart hook
#
# Fires on every Claude Code session start (startup/resume/clear/compact).
# Per agent-teams doc, each teammate's Claude session also fires this hook.
# Per sub-agents doc, subagents do NOT fire this hook (their goal injection
# is handled by squad-spawn baking goal text into the Task prompt).
#
# Reads .squad/goal.md if it exists, returns it as additionalContext so the
# squad goal is in scope for every session turn. The goal ALWAYS comes
# first in that context.
#
# PARTNER MODEL (hard rule #12)
# ------------------------------
# .squad/partner.md — the human's own standing brief, written only by
# squad-partner (told, not inferred) — is appended immediately after the
# goal when it exists and is non-empty. The check is a bare `[ -s ]` size
# test, no jq required: an absent file or a zero-byte one changes nothing,
# byte for byte, versus a build with no partner-model support at all. This
# is the SessionStart half of hard rule #12's two read paths — the other is
# squad-spawn's prompt-baking into subagents, which this hook cannot reach
# (SessionStart does not fire for subagents; see squad-spawn's own hard
# rule #4 handling). A session and an Agent Teams teammate DO fire this
# hook, so this is their path to seeing the partner model without anyone
# re-reading the file mid-session.
#
# OPEN-ESCALATION NOTICE (hard rules #14, #15)
# ----------------------------------------------
# A role that hit a declared `stop:` bound ends its run with
# `status: escalated` on its engagement record (.squad/role-plan-<role>.md,
# templates/role-plan.md) instead of quietly finishing. Left there, a
# stopped squad can look indistinguishable from a finished one to a human
# who wasn't watching. So: after the goal, if one or more escalations are
# still open, append a single line naming the count and pointing at
# .squad/verification.md — the only place the human's ruling can live
# (THE LOAD-BEARING INVARIANT: a role can never mint that ruling; see
# hooks/permission-request.sh's .squad/ reservation, which keeps
# verification.md structurally unwritable by any role).
#
# "Open" = status: escalated on a role-plan record AND that record's
# filename-derived role NOT named in verification.md's frontmatter list
# `resolved_escalations:`. Both inputs are read-only from this hook's side;
# neither is something a role controls once verification.md is squad-verify
# owned. (Residual, stated per the spec: a role CAN flip its own record
# back to `status: active`, which reads here as "no longer open" — that is
# behaviorally identical to never having stopped, the acknowledged
# aspirational half of #14, and not the hole this notice exists to close.)
#
# NO JQ for the escalation count, by design — this repo's stated commitment
# is that the plugin degrades gracefully on a machine without jq, and the
# count is cheap to get with grep + a shell loop + awk (already the house
# style — see skills/squad-verify/scripts/verify.sh's frontmatter_field /
# section_lines). jq stays reserved for what actually needs it here: safe
# JSON-escaping of arbitrary, multi-line, user-authored goal content.
#
# ABSENCE CONTRACT: no .squad/ dir, no role-plan-*.md records, or a count of
# zero produces NO notice — output is byte-identical to a build that never
# shipped this feature. Same contract for the partner model: no
# .squad/partner.md, or a zero-byte one, appends nothing — output is
# byte-identical to a build with no partner-model support. Verified by
# tests/session-start.bats.
#
# Always exits 0. Never blocks session start.

set -u  # no -e: we want to fail-open on errors

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SQUAD_DIR="$PROJECT_DIR/.squad"
GOAL="$SQUAD_DIR/goal.md"
VERIFICATION="$SQUAD_DIR/verification.md"
PARTNER="$SQUAD_DIR/partner.md"

# Drain stdin (the hook input JSON). We don't currently use any fields from
# it — SessionStart fires unconditionally and the goal/notice are the same
# regardless of source (startup vs resume vs clear vs compact).
cat >/dev/null 2>&1 || true

# --- Open-escalation count (no jq — grep + awk only) --------------------------

# frontmatter_of <file> → prints only the lines strictly between the first
# pair of "---" fences. Empty output for a missing file, an unfenced file,
# or a file whose opening fence is never closed — never fatal, never a
# false match against body prose.
frontmatter_of() {
  awk '
    BEGIN { fence = 0 }
    /^---[[:space:]]*$/ { fence++; next }
    fence == 1 { print }
    fence >= 2 { exit }
  ' "$1" 2>/dev/null
}

# role_resolved <role> <verification-file> → success (0) iff <role> appears
# under the frontmatter key `resolved_escalations:` in <verification-file>.
# PR3-SPEC's canonical form is block-style, one role per dashed line —
# handled first below. templates/verification.md's own placeholder shows a
# flow-style `[<role>, <role>, ...]` for the same key, so that form is
# accepted too rather than assumed away; either way an unresolved role reads
# as "not yet resolved," never as a parse error. Any missing file, missing
# key, empty list, or malformed YAML degrades to "not resolved" (1) — never
# fatal.
role_resolved() {
  local role="$1" file="$2"
  [ -f "$file" ] || return 1
  frontmatter_of "$file" | awk -v role="$role" '
    # Flow-style: resolved_escalations: [a, b, c]  (also matches [] empty)
    /^resolved_escalations:[[:space:]]*\[/ {
      line = $0
      sub(/^resolved_escalations:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, items, ",")
      for (k = 1; k <= n; k++) {
        item = items[k]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
        gsub(/^["'"'"']+|["'"'"']+$/, "", item)
        if (item == role) { found = 1; exit }
      }
      next
    }
    # Block-style: resolved_escalations:\n  - a\n  - b
    /^resolved_escalations:[[:space:]]*$/ { in_list = 1; next }
    /^resolved_escalations:/              { in_list = 0 }
    in_list && /^[[:space:]]*-/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/^["'"'"']+|["'"'"']+$/, "", item)
      sub(/[[:space:]]+$/, "", item)
      if (item == role) { found = 1; exit }
      next
    }
    in_list { in_list = 0 }
    END { exit(found ? 0 : 1) }
  ' 2>/dev/null
}

# open_escalation_count <squad-dir> <verification-file> → prints the number
# of .squad/role-plan-<role>.md records with `status: escalated` in their
# frontmatter whose <role> is not listed as resolved. Prints "0" (never
# empty, never non-numeric) on any missing/malformed input.
open_escalation_count() {
  local dir="$1" verification="$2" count=0 f role

  for f in "$dir"/role-plan-*.md; do
    [ -f "$f" ] || continue

    frontmatter_of "$f" | grep -qE '^status:[[:space:]]*escalated\b' 2>/dev/null || continue

    role="${f##*/}"                # strip directory
    role="${role#role-plan-}"      # strip prefix
    role="${role%.md}"             # strip suffix
    [ -z "$role" ] && continue

    role_resolved "$role" "$verification" && continue

    count=$((count + 1))
  done

  printf '%s' "$count"
}

# escalation_notice <count> → prints the one-line notice, or nothing for a
# count of 0 (the absence contract — this must be silent, not "0 open").
escalation_notice() {
  local n="$1"
  [ "$n" -gt 0 ] || return 0
  if [ "$n" -eq 1 ]; then
    printf '[cheeky-squad-os: 1 open escalation is waiting on your ruling — see .squad/verification.md]'
  else
    printf '[cheeky-squad-os: %d open escalations are waiting on your ruling — see .squad/verification.md]' "$n"
  fi
}

NOTICE=$(escalation_notice "$(open_escalation_count "$SQUAD_DIR" "$VERIFICATION")")

# --- Emit ----------------------------------------------------------------------

emit_context() {
  # Emit a SessionStart hookSpecificOutput payload with additionalContext.
  # Prefer jq for robust JSON encoding of arbitrary goal content. Fall back
  # to a static notice if jq is unavailable — naming what is lost (full goal
  # injection) while still surfacing the escalation notice, whose text is
  # entirely our own fixed words plus an integer, never user-authored, and
  # therefore safe to embed without a JSON-escaping library.
  local ctx="$1" notice="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$ctx" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' \
      2>/dev/null || true
  else
    local base='cheeky-squad-os: jq not installed on this system — full goal injection disabled. Install jq (brew install jq / apt-get install jq) to enable. The squad goal file is at .squad/goal.md if present.'
    if [ -n "$notice" ]; then
      base="$base $notice"
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$base"
  fi
}

if [ -f "$GOAL" ]; then
  CONTENT=$(cat "$GOAL" 2>/dev/null || printf '%s' '<failed to read .squad/goal.md>')
  PREAMBLE='[cheeky-squad-os squad goal in scope — every action must serve this outcome]'
  CTX="$PREAMBLE"$'\n\n'"$CONTENT"
else
  CTX='no squad goal set — run /cheeky-squad-os:squad-onboard to set one'
fi

# --- Partner model (hard rule #12) ---------------------------------------------
#
# Appended immediately after the goal — the goal always comes first, this
# always comes second. `[ -s ]` is a plain size test (exists AND non-empty);
# no jq needed to decide whether to append. .squad/partner.md describes the
# human, not the squad, so its presence here does not depend on GOAL
# existing above — a project can have a partner model before it has ever
# run squad-onboard. The content itself still passes through emit_context's
# existing jq path below for safe JSON-escaping, same as the goal always
# has — that dependency on jq is pre-existing, not new here.
if [ -s "$PARTNER" ]; then
  PARTNER_CONTENT=$(cat "$PARTNER" 2>/dev/null || printf '%s' '')
  if [ -n "$PARTNER_CONTENT" ]; then
    PARTNER_PREAMBLE='[cheeky-squad-os partner model in scope — .squad/partner.md, hard rule #12: told, not inferred]'
    CTX="$CTX"$'\n\n'"$PARTNER_PREAMBLE"$'\n\n'"$PARTNER_CONTENT"
  fi
fi

if [ -n "$NOTICE" ]; then
  CTX="$CTX"$'\n\n'"$NOTICE"
fi

emit_context "$CTX" "$NOTICE"

exit 0

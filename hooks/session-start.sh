#!/usr/bin/env bash
# session-start.sh — cheeky-squad-os SessionStart hook
#
# Fires on every Claude Code session start (startup/resume/clear/compact).
# Per agent-teams doc, each teammate's Claude session also fires this hook.
# Per sub-agents doc, subagents do NOT fire this hook (their goal injection
# is handled by squad-spawn baking goal text into the Task prompt).
#
# Reads .squad/goal.md if it exists, returns it as additionalContext so the
# squad goal is in scope for every session turn.
#
# Always exits 0. Never blocks session start.

set -u  # no -e: we want to fail-open on errors

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
GOAL="$PROJECT_DIR/.squad/goal.md"

# Drain stdin (the hook input JSON). We don't currently use any fields from
# it — SessionStart fires unconditionally and the goal is the same regardless
# of source (startup vs resume vs clear vs compact).
cat >/dev/null 2>&1 || true

emit_context() {
  # Emit a SessionStart hookSpecificOutput payload with additionalContext.
  # Prefer jq for robust JSON encoding; fall back to a static notice if jq
  # is unavailable.
  local ctx="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$ctx" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' \
      2>/dev/null || true
  else
    # Without jq, we can't reliably JSON-escape multi-line content. Emit a
    # minimal static notice that points the user at the fix.
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"cheeky-squad-os: jq not installed on this system — full goal injection disabled. Install jq (brew install jq / apt-get install jq) to enable. The squad goal file is at .squad/goal.md if present."}}'
  fi
}

if [ -f "$GOAL" ]; then
  CONTENT=$(cat "$GOAL" 2>/dev/null || printf '%s' '<failed to read .squad/goal.md>')
  PREAMBLE='[cheeky-squad-os squad goal in scope — every action must serve this outcome]'
  emit_context "$PREAMBLE"$'\n\n'"$CONTENT"
else
  emit_context 'no squad goal set — run /cheeky-squad-os:squad-onboard to set one'
fi

exit 0

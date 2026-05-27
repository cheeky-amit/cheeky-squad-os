#!/usr/bin/env bash
# user-prompt-submit.sh — cheeky-squad-os UserPromptSubmit hook
#
# Fires on every user prompt in the main session. Appends a one-line context
# tag reminding the model what the squad goal is, so drift is visible.
#
# v1 is OBSERVATIONAL ONLY. This hook does not block, does not refuse, and
# does not modify the user's prompt. It only adds additionalContext.
#
# Always exits 0.

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
GOAL="$PROJECT_DIR/.squad/goal.md"

# Drain stdin. v1 doesn't use the submitted prompt content — we just inject
# a static one-liner per turn. Future v2 may parse the prompt for drift
# detection; that work is deliberately out of scope here.
cat >/dev/null 2>&1 || true

# Pass-through silently if no goal is set. The SessionStart hook already
# nudged the user about setting one — no need to repeat per-turn.
if [ ! -f "$GOAL" ]; then
  exit 0
fi

# Extract the first non-empty, non-frontmatter, non-heading content line of
# the goal — that's the outcome paragraph. Truncate to 80 chars.
SUMMARY=$(awk '
  BEGIN { in_frontmatter = 0; seen_open = 0 }
  /^---[[:space:]]*$/ {
    if (!seen_open) { in_frontmatter = 1; seen_open = 1; next }
    else if (in_frontmatter) { in_frontmatter = 0; next }
  }
  in_frontmatter { next }
  /^[[:space:]]*$/ { next }
  /^#/ { next }
  { print; exit }
' "$GOAL" 2>/dev/null | cut -c1-80)

if [ -z "$SUMMARY" ]; then
  # Goal file exists but we couldn't find a content line. Fail-open: no tag.
  exit 0
fi

TAG="[squad goal in scope: ${SUMMARY}]"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg tag "$TAG" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $tag}}' \
    2>/dev/null || true
fi
# If jq is missing, fail-open silently — the tag is helpful but not load-bearing.

exit 0

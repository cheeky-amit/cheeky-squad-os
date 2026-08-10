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

# A present v2 export manifest is authoritative. Emit only for a Claude-owned
# snapshot that actually selects Claude; malformed/unknown manifests defer.
# Standalone plugins use their vendored goal snapshot and never substitute a
# live project goal when the package context is missing.
manifest_allows_claude_runtime() {
  local manifest="$1"
  command -v jq >/dev/null 2>&1 || return 1
  jq -e '
    type == "object" and
    ((keys_unsorted - ["schema_version","squad","execution_mode","destination","providers","runtime_owner","export_version"]) | length == 0) and
    .schema_version == 2 and
    (.squad | type == "object") and
    ((.squad | keys_unsorted) - ["id","name","description"] | length == 0) and
    (.squad.id | type == "string" and length <= 63 and test("^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)*$")) and
    (.squad.name | type == "string" and length > 0) and
    (.execution_mode == "one-time" or .execution_mode == "multi-use" or .execution_mode == "evergreen") and
    (.destination == "session" or .destination == "project" or .destination == "user" or .destination == "plugin") and
    (.providers | type == "array" and length > 0 and all(. == "claude" or . == "codex") and length == (unique | length)) and
    .runtime_owner == "claude" and
    (.providers | index("claude") != null) and
    (.export_version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$"))
  ' "$manifest" >/dev/null 2>&1
}

PLUGIN_MANIFEST=''
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_MANIFEST="$CLAUDE_PLUGIN_ROOT/.squad/manifest.json"
fi
PROJECT_MANIFEST="$PROJECT_DIR/.squad/manifest.json"

if [ -n "$PLUGIN_MANIFEST" ] && [ -f "$PLUGIN_MANIFEST" ]; then
  manifest_allows_claude_runtime "$PLUGIN_MANIFEST" || exit 0
  CONTEXT_INDEX="$CLAUDE_PLUGIN_ROOT/.squad/context/index.json"
  GOAL="$CLAUDE_PLUGIN_ROOT/.squad/context/squad-goal.md"
  [ -f "$CONTEXT_INDEX" ] && [ -f "$GOAL" ] || exit 0
  jq -e '
    type == "object" and
    .schema_version == 1 and
    .squad_goal.status == "included" and
    .squad_goal.snapshot == "context/squad-goal.md"
  ' "$CONTEXT_INDEX" >/dev/null 2>&1 || exit 0
elif [ -f "$PROJECT_MANIFEST" ]; then
  manifest_allows_claude_runtime "$PROJECT_MANIFEST" || exit 0
fi

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

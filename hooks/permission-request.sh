#!/usr/bin/env bash
# permission-request.sh — cheeky-squad-os PermissionRequest hook
#
# Fires when Claude Code is about to prompt for permission on a tool call.
# If the call comes from a registered subagent (agent_type set on the hook
# input — confirmed field name per hooks doc + sub-agents doc) AND the call
# is an Edit/Write to a file inside the role's file_scope, auto-approve.
# Otherwise: omit decision and let normal permission flow handle it (user
# is prompted — never silently denied).
#
# v1 scope:
#   - Edit, Write → check tool_input.file_path against role file_scope
#   - Everything else (Bash, MCP tools, …) → defer to user
# v2 may extend to Bash command-path parsing; v1 keeps the surface narrow.
#
# Always exits 0. Fail-open on any error.

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
ROSTER="$PROJECT_DIR/.squad/roster.json"

# Read hook input from stdin into a variable. If anything fails downstream
# we exit 0 with no output, which means "no decision — defer to user".
INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
  exit 0
fi

# jq is required for safe JSON parsing. If it's missing, defer to user
# (fail-open — never auto-approve without a parser we trust).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [ ! -f "$ROSTER" ]; then
  exit 0
fi

# --- Extract input fields ----------------------------------------------------

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Main-session calls (no agent_type) → defer to user. Auto-approval is only
# for subagent/teammate calls where the active role is identifiable.
if [ -z "$AGENT_TYPE" ]; then
  exit 0
fi

# Only Edit and Write are in scope for v1 auto-approval.
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Look up the role's file_scope ------------------------------------------

# jq filter: find the role by name, output one scope glob per line.
SCOPES=$(printf '%s' "$(cat "$ROSTER")" \
  | jq -r --arg name "$AGENT_TYPE" \
      '.roles[] | select(.name == $name) | .file_scope[]?' 2>/dev/null)

if [ -z "$SCOPES" ]; then
  # Unknown agent_type, or role has no file_scope. Defer to user.
  exit 0
fi

# --- Normalize file_path to project-relative ---------------------------------

# Resolve project root to a canonical absolute path.
PROJECT_ABS=$(cd "$PROJECT_DIR" 2>/dev/null && pwd)
if [ -z "$PROJECT_ABS" ]; then
  exit 0
fi

case "$FILE_PATH" in
  /*)
    # Absolute path. Must be inside project root to be considered.
    case "$FILE_PATH" in
      "$PROJECT_ABS"/*) REL_PATH="${FILE_PATH#$PROJECT_ABS/}" ;;
      "$PROJECT_ABS")   REL_PATH="" ;;
      *) exit 0 ;;  # outside project root → defer
    esac
    ;;
  *)
    # Already relative.
    REL_PATH="$FILE_PATH"
    ;;
esac

# --- Match against each scope glob ------------------------------------------

# Glob semantics:
#   "<prefix>/**"  → match any path whose first segments are <prefix>
#   "*.<ext>"      → match any file ending in .<ext> at the same directory depth
#   Other patterns → fall through to bash [[ pattern matching, which is
#                    permissive (treats * as "anything including /"). User
#                    keeps final say since unmatched paths just defer.
path_in_scope() {
  local rel="$1"
  local glob="$2"

  # Strip trailing "/**" → recursive directory match
  case "$glob" in
    */\*\*)
      local prefix="${glob%/\*\*}"
      if [ "$rel" = "$prefix" ]; then return 0; fi
      case "$rel" in
        "$prefix"/*) return 0 ;;
      esac
      return 1
      ;;
    \*\*)
      # Bare "**" → match anything
      return 0
      ;;
  esac

  # Fall back to bash pattern matching for everything else
  # shellcheck disable=SC2053
  [[ "$rel" == $glob ]] && return 0
  return 1
}

MATCHED=0
while IFS= read -r GLOB; do
  [ -z "$GLOB" ] && continue
  if path_in_scope "$REL_PATH" "$GLOB"; then
    MATCHED=1
    break
  fi
done <<< "$SCOPES"

if [ "$MATCHED" -eq 1 ]; then
  # Emit allow decision. permissionRule pins future identical calls so we
  # don't re-prompt or re-evaluate every turn.
  jq -n --arg path "$FILE_PATH" --arg tool "$TOOL_NAME" --arg role "$AGENT_TYPE" \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "allow", permissionRule: ("cheeky-squad-os: \($role) owns \($path)")}}}' \
    2>/dev/null || true
fi
# No match → no output → defer to user. Never silently deny.

exit 0

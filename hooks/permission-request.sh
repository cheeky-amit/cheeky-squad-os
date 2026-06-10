#!/usr/bin/env bash
# permission-request.sh — cheeky-squad-os PermissionRequest hook
#
# Fires when Claude Code is about to prompt for permission on a tool call.
# If the call comes from a registered subagent (agent_type set on the hook
# input — confirmed field name per hooks doc + sub-agents doc) it may be
# auto-approved on one of two narrow surfaces; everything else defers to the
# user (no decision emitted → normal permission flow → user prompted; never
# silently denied):
#
#   1. Edit/Write to a file inside the role's file_scope.
#   2. Bash that does pure in-sandbox SCAFFOLDING (mkdir/touch/cp/ln) where
#      EVERY path operand resolves inside the role's environment.workspace.
#      This is the role working freely inside its own sandbox. Anything that
#      cannot be proven contained — a different verb, an operand outside the
#      workspace, any shell metacharacter (so we can't reason about it), or a
#      role with no declared workspace — defers to the user. Installs, network,
#      and global mutations are NOT on this list by design: they are the
#      provisioner's "propose to the user" path, not the running role's.
#
# The two surfaces share the same containment primitives (normalize-to-relative,
# reject ".." traversal, fail-closed on doubt) — auto-approving Bash never
# reopens the path-traversal hole hardened on the Edit/Write surface.
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
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Main-session calls (no agent_type) → defer to user. Auto-approval is only
# for subagent/teammate calls where the active role is identifiable.
if [ -z "$AGENT_TYPE" ]; then
  exit 0
fi

# Resolve project root to a canonical absolute path (shared by both surfaces).
PROJECT_ABS=$(cd "$PROJECT_DIR" 2>/dev/null && pwd)
if [ -z "$PROJECT_ABS" ]; then
  exit 0
fi

# --- Shared containment primitives -------------------------------------------

# normalize_rel <raw-path> → prints the project-relative form on stdout.
# Returns 1 if the path is absolute and outside the project root (caller defers).
normalize_rel() {
  local p="$1" rel
  case "$p" in
    /*)
      case "$p" in
        "$PROJECT_ABS"/*) rel="${p#"$PROJECT_ABS"/}" ;;
        "$PROJECT_ABS")   rel="" ;;
        *) return 1 ;;  # absolute path outside project → defer
      esac
      ;;
    *)
      rel="$p"  # already relative
      ;;
  esac
  printf '%s' "$rel"
  return 0
}

# has_traversal <rel> → returns 0 if the relative path contains a ".." segment.
# A ".." could escape scope/sandbox even when the path textually matches; an
# auto-APPROVE decision must never depend on caller pre-normalization.
has_traversal() {
  case "$1" in
    ..|../*|*/..|*/../*) return 0 ;;
  esac
  return 1
}

# emit_allow → print the minimal allow decision. The PermissionRequest decision
# object's documented shape is decision.behavior ("allow"|"deny"); there is NO
# `permissionRule` field (silently ignored). To persist a rule the documented
# field is `updatedPermissions`; v1 leaves it unset and re-evaluates each call.
emit_allow() {
  jq -n \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "allow"}}}' \
    2>/dev/null || true
}

# rel_under_dir <rel> <dir> → returns 0 if <rel> is <dir> itself or nested
# beneath it. <dir> is a plain prefix (the role's workspace), not a glob.
rel_under_dir() {
  local rel="$1" dir="$2"
  case "$rel" in
    "$dir") return 0 ;;
    "$dir"/*) return 0 ;;
  esac
  return 1
}

# path_in_scope <rel> <glob> — file_scope glob matcher (Edit/Write surface).
# Glob semantics:
#   "<prefix>/**"        → any path whose first segments are <prefix>
#   "**"                 → match anything
#   other patterns       → segment-for-segment bash [[ ]] matching: "*" never
#                          crosses "/" (e.g. "*.md" matches "notes.md" but NOT
#                          "src/notes.md"; "data/*" matches "data/x" but NOT
#                          "data/sub/x"). Unmatched paths defer — fail closed.
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

  # bash [[ == ]] lets "*" cross "/" (no FNM_PATHNAME), so before falling
  # through, require glob and rel to have the SAME number of "/" — each "*"
  # then matches within a single segment. Catches both the no-"/" case
  # ("*.md" vs "src/notes.md") and the mid-path case ("data/*" vs
  # "data/sub/secret"), which would otherwise silently over-approve.
  local g_slashes="${glob//[!\/]/}" r_slashes="${rel//[!\/]/}"
  if [ "${#g_slashes}" -ne "${#r_slashes}" ]; then
    return 1
  fi

  # Fall back to bash pattern matching for everything else
  # shellcheck disable=SC2053
  [[ "$rel" == $glob ]] && return 0
  return 1
}

# --- Branch on tool ----------------------------------------------------------

case "$TOOL_NAME" in
  Edit|Write)
    # ----- Surface 1: in-scope Edit/Write ------------------------------------
    if [ -z "$FILE_PATH" ]; then
      exit 0
    fi

    SCOPES=$(printf '%s' "$(cat "$ROSTER")" \
      | jq -r --arg name "$AGENT_TYPE" \
          '.roles[] | select(.name == $name) | .file_scope[]?' 2>/dev/null)
    if [ -z "$SCOPES" ]; then
      exit 0  # unknown role, or no file_scope → defer
    fi

    REL_PATH=$(normalize_rel "$FILE_PATH") || exit 0
    if has_traversal "$REL_PATH"; then
      exit 0  # never auto-approve traversal — defer to user
    fi

    MATCHED=0
    while IFS= read -r GLOB; do
      [ -z "$GLOB" ] && continue
      if path_in_scope "$REL_PATH" "$GLOB"; then
        MATCHED=1
        break
      fi
    done <<< "$SCOPES"

    if [ "$MATCHED" -eq 1 ]; then
      emit_allow
    fi
    exit 0
    ;;

  Bash)
    # ----- Surface 2: in-sandbox scaffolding ---------------------------------
    if [ -z "$COMMAND" ]; then
      exit 0
    fi

    # The role's sandbox root. No declared workspace → no sandbox → defer.
    WS=$(printf '%s' "$(cat "$ROSTER")" \
      | jq -r --arg name "$AGENT_TYPE" \
          '.roles[] | select(.name == $name) | .environment.workspace // empty' 2>/dev/null)
    if [ -z "$WS" ]; then
      exit 0
    fi
    WS="${WS%/}"

    # Reject any shell metacharacter: substitution, chaining, redirection,
    # subshell, brace expansion, escapes, newline. We can only reason about a
    # plain "verb operand operand …" line; anything else defers (fail closed).
    case "$COMMAND" in
      *';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'`'*|*'$'*|*\\*|*'('*|*')'*|*'{'*|*'}'*) exit 0 ;;
    esac
    case "$COMMAND" in
      *"
"*) exit 0 ;;  # embedded newline
    esac

    # Tokenize on whitespace. First token is the verb.
    read -ra TOKENS <<< "$COMMAND"
    VERB="${TOKENS[0]:-}"
    case "$VERB" in
      mkdir|touch|cp|ln) ;;
      *) exit 0 ;;  # only non-destructive scaffolding verbs are auto-approved
    esac

    # Every non-flag operand must resolve inside the workspace. Zero operands
    # (e.g. a bare verb) → nothing to approve → defer.
    OPERANDS=0
    for tok in "${TOKENS[@]:1}"; do
      case "$tok" in
        -*) continue ;;  # a flag, not a path operand
      esac
      OPERANDS=$((OPERANDS + 1))
      REL=$(normalize_rel "$tok") || exit 0   # outside project → defer
      if has_traversal "$REL"; then
        exit 0  # traversal → defer
      fi
      if ! rel_under_dir "$REL" "$WS"; then
        exit 0  # operand escapes the sandbox → defer
      fi
    done

    if [ "$OPERANDS" -ge 1 ]; then
      emit_allow
    fi
    exit 0
    ;;

  *)
    exit 0  # every other tool defers to the user
    ;;
esac

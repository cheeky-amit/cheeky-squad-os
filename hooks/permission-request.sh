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
#   1. Edit/Write to a file inside the role's file_scope — EXCEPT under
#      .squad/, which is structurally reserved (see below).
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
# THE .squad/ STRUCTURAL RESERVATION (v0.4.1)
# -------------------------------------------
# .squad/ holds squad STATE, not work product. Consulting file_scope there was a
# forgery hole: a role whose scope is broad — "**", or ".squad/**" — matched, and
# therefore auto-approved writes to another role's hand-off outbox, another
# role's goal, the squad goal, the roster, and verification.md. That defeats the
# v0.3.0 outbox guarantee (true only for narrowly-scoped roles) and hard rule #10
# (a role could write its own verdict).
#
# So: a path under .squad/ NEVER consults file_scope. A role is granted exactly
# the .squad/ paths derived from its OWN sanitized agent_type, and every other
# .squad/ write defers to the user. Derived-not-declared is what makes the grant
# unforgeable — a role cannot widen it, because the roster entry the grant reads
# is selected by the agent_type Claude Code reports, and roster.json itself is
# now deferred.
#
# Granted:
#   - .squad/role-plan-<agent>.md        its own engagement record (rule #11)
#   - .squad/role-comm-<agent>--*        its own hand-off outbox
#   - <its own environment.workspace>/** its own sandbox (hard rule #8)
# Deferred: every other .squad/ path, for every role, at every scope.
#
# THE PLAN GATE (hard rule #11)
# -----------------------------
# Both auto-approve surfaces above — in-scope Edit/Write and in-sandbox Bash —
# are additionally conditioned on the role having published its engagement
# record at .squad/role-plan-<agent>.md. Autonomy is purchased with intent.
#
# The record's own path is granted UNCONDITIONALLY (see squad_grant): a role
# cannot publish its plan if publishing the plan required a plan. Everything
# else waits on it.
#
# The gate DEFERS, it never denies. A role that declines to declare gets
# exactly the behavior an out-of-scope write got in v0.4.x — the human is
# asked. That is also why a pre-v1.0 roster needs no migration.
#
# Note this is a net WIDENING of three derived paths and a net NARROWING of
# everything else: a role with a narrow scope that never registered its record
# or outbox now gets both structurally, and a role with a broad scope loses the
# rest. Stated plainly because "the hook only ever removes an auto-approval" is
# no longer true. What is true: the hook only ever grants a role its own state.
#
# Always exits 0. Fail-open on any error.

set -u

# Byte-order collation for every case/glob comparison below — locale-dependent
# ranges must never change a containment decision.
LC_ALL=C
export LC_ALL

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

# --- Resolve the project root ------------------------------------------------
#
# A role running under `isolation: worktree` (hard rule #7) works in a git
# worktree, not the main checkout — and its .squad/ lives there. Resolving
# solely from CLAUDE_PROJECT_DIR is therefore not safe: if that variable points
# at the main checkout, this hook reads the wrong roster (or none), every
# containment check runs against the wrong root, and the role gets no
# auto-approval at all.
#
# The hook input carries `cwd` — where the tool call is actually happening.
# Prefer whichever of the two candidates actually holds a roster. Both come
# from Claude Code, not from the role, so neither is attacker-controlled; and
# if neither has one we defer exactly as before.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ ! -f "$PROJECT_DIR/.squad/roster.json" ]; then
  HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  if [ -n "$HOOK_CWD" ] && [ -f "$HOOK_CWD/.squad/roster.json" ]; then
    PROJECT_DIR="$HOOK_CWD"
  fi
fi
ROSTER="$PROJECT_DIR/.squad/roster.json"

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

# has_engagement_record <agent> → returns 0 if this role has published its
# engagement record (hard rule #11). This is the plan gate: autonomy is
# purchased with intent. Until the record exists a role's in-scope Edit/Write
# and in-sandbox Bash DEFER — they are never denied, so a role that declines to
# plan simply falls back to v0.4.x's out-of-scope behavior (the human is asked).
#
# Deliberately a bare file-existence check, not a schema validation: the gate's
# job is "did you declare before acting", and squad-verify is what judges the
# declaration's quality. A hook that parsed the record could fail closed on a
# malformed one, which would be deny-shaped — this plugin never denies.
has_engagement_record() {
  local agent="$1"
  safe_agent_name "$agent" || return 1
  [ -f "$PROJECT_ABS/.squad/role-plan-$agent.md" ]
}

# rel_under_squad <rel> → returns 0 if <rel> is the .squad/ dir or nested in it.
# Anything matching this takes the reservation path and never sees file_scope.
rel_under_squad() {
  case "$1" in
    .squad|.squad/*) return 0 ;;
  esac
  return 1
}

# safe_agent_name <agent_type> → returns 0 if the name is safe to build a path
# from: lowercase kebab, no dots, no slashes, no leading hyphen. A name failing
# this is never used in a derived path (it could otherwise smuggle "../" or a
# glob metacharacter into the grant) — the role simply gets no .squad/ grant.
safe_agent_name() {
  case "$1" in
    ''|-*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# squad_grant <rel> <agent> <workspace> → returns 0 if this role may write this
# .squad/ path. Order is load-bearing: the role's own outbox is granted BEFORE
# the reserved-artifact check, because the outbox lives inside that namespace.
#
#   1. own outbox  .squad/role-comm-<agent>--*      → allow
#   2. reserved squad artifact                      → defer (never grantable)
#   3. inside the role's own declared workspace     → allow (hard rule #8)
#   4. anything else under .squad/                  → defer
#
# Step 2 exists so a roster that declares a wide environment.workspace (say
# ".squad/") cannot swallow another role's contract paths through step 3.
squad_grant() {
  local rel="$1" agent="$2" ws="$3"

  if safe_agent_name "$agent"; then
    case "$rel" in
      # The engagement record (hard rule #11). ALWAYS granted, unconditionally
      # — it is the bootstrap: a role cannot publish its plan if publishing the
      # plan required a plan. This is also what lets a pre-v1.0 roster upgrade
      # with no migration, since the grant is derived, not registered.
      ".squad/role-plan-$agent.md") return 0 ;;
      # The role's own hand-off outbox — granted only once it has declared
      # intent. Publishing a hand-off is acting; #11 applies.
      ".squad/role-comm-$agent--"*)
        has_engagement_record "$agent" && return 0
        return 1
        ;;
    esac
  fi

  # Reserved: squad-wide state and any role's per-role artifacts. Structurally
  # owned by the skills that write them; never reachable via a workspace grant.
  case "$rel" in
    .squad/goal.md|.squad/roster.json|.squad/roster.md|.squad/verification.md) return 1 ;;
    .squad/partner.md) return 1 ;;
    .squad/role-goal-*|.squad/role-comm-*|.squad/role-plan-*) return 1 ;;
    .squad/world/*) return 1 ;;
    .squad/squads/*) return 1 ;;
  esac

  # The role's own sandbox. Empty workspace, or one that is .squad/ itself,
  # grants nothing — a sandbox must be strictly nested to be containable.
  if [ -n "$ws" ] && [ "$ws" != ".squad" ] && rel_under_dir "$rel" "$ws"; then
    return 0
  fi

  return 1
}

# --- Branch on tool ----------------------------------------------------------

case "$TOOL_NAME" in
  Edit|Write)
    # ----- Surface 1: in-scope Edit/Write ------------------------------------
    if [ -z "$FILE_PATH" ]; then
      exit 0
    fi

    REL_PATH=$(normalize_rel "$FILE_PATH") || exit 0
    if has_traversal "$REL_PATH"; then
      exit 0  # never auto-approve traversal — defer to user
    fi

    # The role must be registered before any grant is considered — an
    # unregistered agent_type gets nothing, on either surface below.
    ROLE_JSON=$(printf '%s' "$(cat "$ROSTER")" \
      | jq -c --arg name "$AGENT_TYPE" \
          'first(.roles[] | select(.name == $name)) // empty' 2>/dev/null)
    if [ -z "$ROLE_JSON" ]; then
      exit 0  # unknown role → defer
    fi

    # ----- The .squad/ structural reservation --------------------------------
    # Squad state never consults file_scope. See the header for why.
    if rel_under_squad "$REL_PATH"; then
      WS=$(printf '%s' "$ROLE_JSON" \
        | jq -r '.environment.workspace // empty' 2>/dev/null)
      WS="${WS%/}"
      if squad_grant "$REL_PATH" "$AGENT_TYPE" "$WS"; then
        emit_allow
      fi
      exit 0  # granted or not, .squad/ never falls through to file_scope
    fi

    # ----- The plan gate (hard rule #11) -------------------------------------
    # Outside .squad/, scope auto-approval is conditioned on the role having
    # declared its intent first. Defer — never deny — until it has.
    if ! has_engagement_record "$AGENT_TYPE"; then
      exit 0
    fi

    SCOPES=$(printf '%s' "$ROLE_JSON" | jq -r '.file_scope[]?' 2>/dev/null)
    if [ -z "$SCOPES" ]; then
      exit 0  # no file_scope → defer
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

    # The plan gate applies to the sandbox surface too (hard rule #11) — a role
    # scaffolding its workspace is still acting, and intent is bought first.
    if ! has_engagement_record "$AGENT_TYPE"; then
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

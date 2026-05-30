#!/usr/bin/env bash
# spawn.sh — Multi-use mode dispatch helper for cheeky-squad-os.
#
# Pre-creates one git worktree per active role under .claude/worktrees/<role-name>/
# (branch squad-<role-name>) so each Multi-use teammate can be pointed at an
# isolated copy of the repo. This script ONLY creates the worktrees — it does
# NOT launch any Claude session and bakes no prompt. The squad-spawn skill (the
# team lead) is responsible for spawning teammates (Agent Teams, by referencing
# each .claude/agents/<role>.md by name) and may direct each teammate to its
# worktree path from the JSON below.
#
# Invoked by the squad-spawn skill via Bash. NOT invoked directly by users.
#
# Inputs:
#   $1 — path to .squad/roster.json (default: .squad/roster.json relative to CWD)
#   $2 — path to .squad/goal.md (default: .squad/goal.md relative to CWD)
#
# Outputs (stdout, one JSON object per line — easy to parse by the skill):
#   {"role": "<name>", "worktree": "<absolute path>", "branch": "squad-<name>", "status": "created|exists"}
#   {"summary": {"created": N, "existed": M, "errors": K}}
#
# Errors go to stderr. Exit 0 on full success, 1 on any per-role error.

set -euo pipefail

ROSTER="${1:-.squad/roster.json}"
GOAL="${2:-.squad/goal.md}"
WORKTREE_BASE=".claude/worktrees"

err() { echo "spawn.sh: $*" >&2; }

# --- Preflight ---------------------------------------------------------------

if [ ! -f "$GOAL" ]; then
  err "no squad goal at $GOAL — run /cheeky-squad-os:squad-onboard"
  exit 1
fi

if [ ! -f "$ROSTER" ]; then
  err "no roster at $ROSTER — run /cheeky-squad-os:squad-role"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed. Install with: brew install jq (macOS) / apt-get install jq (Linux)"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  err "git is required but not installed"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "not inside a git repository — worktrees require a git repo. run 'git init' first."
  exit 1
fi

# Agent Teams env check — the skill is responsible for the user-facing flow
# (offer-to-enable, fall-back-to-subagents). spawn.sh just refuses cleanly
# so the skill can handle the response.
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  err "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set to 1 — Agent Teams disabled"
  err "the squad-spawn skill should have offered to enable this or fallen back to subagents"
  exit 1
fi

MODE=$(awk '/^mode:/ {print $2; exit}' "$GOAL")
if [ "$MODE" != "multi-use" ]; then
  err "spawn.sh is for multi-use mode only — goal mode is '$MODE'"
  err "for one-time mode, use the Agent tool directly; for evergreen, see the squad-spawn skill body"
  exit 1
fi

# --- Worktree creation per active role ---------------------------------------

mkdir -p "$WORKTREE_BASE"

CREATED=0
EXISTED=0
ERRORS=0

# Read active role names from roster.json
ROLES=$(jq -r '.roles[] | select(.active == true) | .name' "$ROSTER")

if [ -z "$ROLES" ]; then
  err "no active roles in roster — nothing to spawn"
  exit 1
fi

while IFS= read -r ROLE; do
  [ -z "$ROLE" ] && continue
  WT_PATH="$WORKTREE_BASE/$ROLE"
  # Branch name: squad-<role>. Branches from origin/HEAD (worktrees doc default)
  # unless worktree.baseRef is set to "head" in settings.
  BRANCH="squad-$ROLE"

  # Already-registered check. `git worktree list --porcelain` prints CANONICAL
  # (symlink-resolved) absolute paths, so compare against the resolved physical
  # path (pwd -P) with a full-line literal match — a substring grep on $(pwd)
  # breaks on symlinked roots (e.g. macOS /tmp -> /private/tmp).
  if [ -d "$WT_PATH" ]; then
    WT_REAL=$(cd "$WT_PATH" 2>/dev/null && pwd -P || true)
    if [ -n "$WT_REAL" ] && git worktree list --porcelain \
        | awk '/^worktree /{print $2}' | grep -Fxq "$WT_REAL"; then
      printf '{"role":"%s","worktree":"%s","branch":"%s","status":"exists"}\n' "$ROLE" "$WT_REAL" "$BRANCH"
      EXISTED=$((EXISTED + 1))
      continue
    fi
  fi

  if git worktree add -B "$BRANCH" "$WT_PATH" 2>/dev/null; then
    WT_ABS=$(cd "$WT_PATH" && pwd -P)
    printf '{"role":"%s","worktree":"%s","branch":"%s","status":"created"}\n' "$ROLE" "$WT_ABS" "$BRANCH"
    CREATED=$((CREATED + 1))
  elif WT_ABS=$(cd "$WT_PATH" 2>/dev/null && pwd -P) \
      && [ -n "$WT_ABS" ] \
      && git worktree list --porcelain | awk '/^worktree /{print $2}' | grep -Fxq "$WT_ABS"; then
    # add failed only because the path is already a registered worktree → idempotent
    printf '{"role":"%s","worktree":"%s","branch":"%s","status":"exists"}\n' "$ROLE" "$WT_ABS" "$BRANCH"
    EXISTED=$((EXISTED + 1))
  else
    err "failed to create worktree for role '$ROLE' at $WT_PATH"
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$ROLES"

# --- Summary -----------------------------------------------------------------

printf '{"summary":{"created":%d,"existed":%d,"errors":%d}}\n' "$CREATED" "$EXISTED" "$ERRORS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0

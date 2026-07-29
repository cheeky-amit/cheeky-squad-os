#!/usr/bin/env bash
# spawn.sh — Multi-use mode dispatch helper for cheeky-squad-os.
#
# Two subcommands:
#
#   spawn.sh [roster] [goal]     Pre-creates one git worktree per active role
#                                 under .claude/worktrees/<role-name>/ (branch
#                                 squad-<role-name>) so each Multi-use teammate
#                                 can be pointed at an isolated copy of the
#                                 repo. Launches no teammate, bakes no prompt.
#
#   spawn.sh collect [roster]    Collects each active role's engagement
#                                 record out of its worktree and into the
#                                 project root's .squad/. See "collect" below.
#
# Invoked by the squad-spawn skill via Bash. NOT invoked directly by users.
#
# --- spawn (default) ----------------------------------------------------------
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
#
# --- collect -------------------------------------------------------------
#
# The problem: a role running under `isolation: worktree` (hard rule #7)
# writes its engagement record (.squad/role-plan-<role>.md, hard rule #11)
# INSIDE the worktree. A git worktree's `.git` is a FILE — a pointer back to
# the main checkout's object store, not a directory — and the worktree itself
# lives entirely outside the main checkout. So the record ends up at
# .claude/worktrees/<role>/.squad/role-plan-<role>.md, and at the project
# root — where squad-verify and squad-spawn's synthesis step read — it is
# invisible. The same is true of a role's belief-ledger claims file
# (.squad/world/claims-<role>.md, hard rule #13) — it too is written inside
# the worktree and is invisible at the root until collected.
#
# `collect` closes that gap: for each ACTIVE role (per roster.json) with a
# worktree under .claude/worktrees/<role>/, it copies BOTH
# .squad/role-plan-<role>.md and .squad/world/claims-<role>.md from the
# worktree to the project root, newer-mtime wins, independently per artifact
# (a role can have collected one and not the other — e.g. it published its
# record but never asserted a belief this run).
#
# It copies NOTHING else under .squad/. permission-request.sh's .squad/
# structural reservation (v0.4.1) guarantees a role can only ever WRITE its
# own record, its own claims file, and its own outbox; `collect` is that same
# guarantee applied on the read/consolidate side — it names exactly the two
# files it moves, and never globs or directory-copies .squad/.
#
# Extension seam: if a later release gives a role a third contract artifact
# under .squad/, collecting it is one more collect_artifact() call below with
# that filename — do not widen this to a directory copy to get there.
#
# Inputs:
#   $1 — path to .squad/roster.json (default: .squad/roster.json relative to
#        CWD). CWD is assumed to be the project root, same as spawn's default.
#
# Outputs (stdout, one JSON object per line — one PER ARTIFACT per role, so
# two lines per role with a worktree):
#   {"role": "<name>", "artifact": ".squad/role-plan-<name>.md", "status": "copied|skipped-no-worktree|skipped-not-newer|error"}
#   {"role": "<name>", "artifact": ".squad/world/claims-<name>.md", "status": "copied|skipped-no-worktree|skipped-not-newer|error"}
#   {"summary": {"collected": N, "skipped": M, "errors": K}}
#
# Errors go to stderr. Exit non-zero ONLY on a real per-role copy error —
# never merely because nothing was collected. Exit 0 otherwise.

set -euo pipefail

WORKTREE_BASE=".claude/worktrees"

err() { echo "spawn.sh: $*" >&2; }

# --- collect -------------------------------------------------------------

# collect_artifact <role> <filename>
# Copies .claude/worktrees/<role>/.squad/<filename> to .squad/<filename> at
# the project root if the worktree's copy is newer than the root's (or the
# root has none yet). Prints one JSON status line and updates the running
# COLLECTED/SKIPPED/COLLECT_ERRORS counters. <filename> may itself contain a
# "/" (e.g. "world/claims-<role>.md") — the destination's parent directory is
# created on demand so a nested contract artifact collects the same way a
# flat one does; this does NOT widen the copy to a directory (see header).
# Two artifacts are collected today, independently: the engagement record
# and the belief-ledger claims file — see the extension-seam note above.
collect_artifact() {
  local role="$1" filename="$2"
  local wt_dir="$WORKTREE_BASE/$role"
  local src="$wt_dir/.squad/$filename"
  local dst=".squad/$filename"

  if [ ! -d "$wt_dir" ] || [ ! -f "$src" ]; then
    printf '{"role":"%s","artifact":".squad/%s","status":"skipped-no-worktree"}\n' "$role" "$filename"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [ -f "$dst" ] && ! [ "$src" -nt "$dst" ]; then
    printf '{"role":"%s","artifact":".squad/%s","status":"skipped-not-newer"}\n' "$role" "$filename"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  if cp -p "$src" "$dst" 2>/dev/null; then
    printf '{"role":"%s","artifact":".squad/%s","status":"copied"}\n' "$role" "$filename"
    COLLECTED=$((COLLECTED + 1))
  else
    err "failed to copy $src to $dst for role '$role'"
    printf '{"role":"%s","artifact":".squad/%s","status":"error"}\n' "$role" "$filename"
    COLLECT_ERRORS=$((COLLECT_ERRORS + 1))
  fi
}

cmd_collect() {
  local roster="${1:-.squad/roster.json}"

  if [ ! -f "$roster" ]; then
    err "no roster at $roster — run /cheeky-squad-os:squad-role"
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required but not installed. Install with: brew install jq (macOS) / apt-get install jq (Linux)"
    exit 1
  fi

  # Root for the collected records to land in. Created even when there is
  # nothing to collect, matching cmd_spawn's mkdir -p of its own base dir.
  mkdir -p .squad

  COLLECTED=0
  SKIPPED=0
  COLLECT_ERRORS=0

  local roles
  roles=$(jq -r '.roles[] | select(.active == true) | .name' "$roster")

  if [ -n "$roles" ]; then
    while IFS= read -r role; do
      [ -z "$role" ] && continue
      collect_artifact "$role" "role-plan-$role.md"
      collect_artifact "$role" "world/claims-$role.md"
    done <<< "$roles"
  fi

  printf '{"summary":{"collected":%d,"skipped":%d,"errors":%d}}\n' "$COLLECTED" "$SKIPPED" "$COLLECT_ERRORS"

  if [ "$COLLECT_ERRORS" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# --- spawn (default) ----------------------------------------------------------

cmd_spawn() {
  ROSTER="${1:-.squad/roster.json}"
  GOAL="${2:-.squad/goal.md}"

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
      WT_REAL=$( (cd "$WT_PATH" 2>/dev/null && pwd -P) || true )
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
}

# --- Dispatch ------------------------------------------------------------------

SUBCOMMAND="${1:-}"
case "$SUBCOMMAND" in
  collect)
    shift
    cmd_collect "$@"
    ;;
  *)
    cmd_spawn "$@"
    ;;
esac

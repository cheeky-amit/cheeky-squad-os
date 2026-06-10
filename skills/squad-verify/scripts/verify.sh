#!/usr/bin/env bash
# verify.sh — Definition-of-done evidence scaffold for cheeky-squad-os.
#
# READ-ONLY. Gathers the mechanical half of verification so the squad-verify
# skill can judge each Definition-of-done signal with evidence in hand:
#   - extracts the goal's "## Definition of done" bullets (signals)
#   - counts deliverable files under each ACTIVE role's file_scope
#   - checks each active role's role-goal file is present
#
# It does NOT decide PASS/FAIL — every signal is emitted as "unverified".
# Deciding is the skill's job ("synthesis summarizes; verification decides"),
# with this output as the scaffold. The script never writes any file.
#
# Invoked by the squad-verify skill via Bash, from the PROJECT ROOT (file_scope
# globs are project-relative). NOT invoked directly by users.
#
# Inputs (positional):
#   $1 — path to .squad/roster.json (default: .squad/roster.json relative to CWD)
#   $2 — path to .squad/goal.md     (default: .squad/goal.md relative to CWD)
#
# Outputs (stdout, one JSON object per line — easy for the skill to parse):
#   {"signal":"<bullet text>","status":"unverified"}                per DoD signal
#   {"role":"<name>","scope":[…],"files_found":N,"role_goal_present":bool}
#                                                                   per active role
#   {"summary":true,"roles":N,"signals":N,"errors":K}               final line
#
# Errors go to stderr. Exit 0 after preflight even with 0 signals or role
# errors (the skill reads the counts); exit 1 only on preflight failure.

set -u  # no -e: a partial scaffold beats a dead one — count errors instead

ROSTER="${1:-.squad/roster.json}"
GOAL="${2:-.squad/goal.md}"

err() { echo "verify.sh: $*" >&2; }

# --- Preflight ---------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed. Install with: brew install jq (macOS) / apt-get install jq (Linux)"
  exit 1
fi

if [ ! -f "$GOAL" ]; then
  err "no squad goal at $GOAL — run /cheeky-squad-os:squad-onboard"
  exit 1
fi

if [ ! -f "$ROSTER" ]; then
  err "no roster at $ROSTER — run /cheeky-squad-os:squad-role"
  exit 1
fi

if ! jq -e . "$ROSTER" >/dev/null 2>&1; then
  err "roster at $ROSTER is not valid JSON"
  exit 1
fi

ERRORS=0

# --- Signals: the goal's Definition-of-done bullets ----------------------------
#
# Parse rules (templates/goal.md ships an HTML comment block INSIDE the
# "## Definition of done" section, so comment-skipping is mandatory):
#   - skip YAML frontmatter between the first pair of "---" fences
#   - strip <!-- … --> comments, including multi-line blocks
#   - collect "- " bullet lines inside "## Definition of done" only,
#     stopping at the next "## " heading

DOD_BULLETS=$(awk '
  BEGIN { fm = 0; seen_fence = 0; in_comment = 0; in_dod = 0 }
  /^---[[:space:]]*$/ {
    if (!seen_fence) { fm = 1; seen_fence = 1; next }
    else if (fm)     { fm = 0; next }
  }
  fm { next }
  {
    # Strip HTML comments. Handles same-line and multi-line blocks.
    if (in_comment) {
      e = index($0, "-->")
      if (e > 0) { $0 = substr($0, e + 3); in_comment = 0 } else next
    }
    while ((s = index($0, "<!--")) > 0) {
      rest = substr($0, s + 4)
      e = index(rest, "-->")
      if (e > 0) { $0 = substr($0, 1, s - 1) substr(rest, e + 3) }
      else       { $0 = substr($0, 1, s - 1); in_comment = 1; break }
    }
  }
  /^##[[:space:]]/ {
    in_dod = (tolower($0) ~ /^##[[:space:]]+definition of done[[:space:]]*$/) ? 1 : 0
    next
  }
  in_dod && /^-[[:space:]]+[^[:space:]]/ {
    sub(/^-[[:space:]]+/, "")
    sub(/[[:space:]]+$/, "")
    print
  }
' "$GOAL" 2>/dev/null)

SIGNAL_COUNT=0
while IFS= read -r SIG; do
  [ -z "$SIG" ] && continue
  jq -nc --arg s "$SIG" '{signal: $s, status: "unverified"}'
  SIGNAL_COUNT=$((SIGNAL_COUNT + 1))
done <<< "$DOD_BULLETS"

# --- Role deliverables: files found under each active role's file_scope --------

# count_glob <glob> → prints the number of regular files the glob covers.
# Mirrors the PermissionRequest hook's semantics: "prefix/**" is the whole
# subtree, bare "**" is the whole project (minus .git), and any other glob
# expands with pathname rules where "*" never crosses a "/".
count_glob() {
  local glob="$1" n=0 f
  case "$glob" in
    \*\*)
      n=$(find . -path ./.git -prune -o -type f -print 2>/dev/null | wc -l | tr -d '[:space:]')
      ;;
    */\*\*)
      local prefix="${glob%/\*\*}"
      if [ -d "$prefix" ]; then
        n=$(find "$prefix" -type f 2>/dev/null | wc -l | tr -d '[:space:]')
      fi
      ;;
    *)
      while IFS= read -r f; do
        [ -f "$f" ] && n=$((n + 1))
      done < <(compgen -G "$glob" 2>/dev/null || true)
      ;;
  esac
  printf '%s' "$n"
}

ROLE_COUNT=0
ROLES_JSON=$(jq -c '.roles[]? | select(.active == true)' "$ROSTER" 2>/dev/null)

while IFS= read -r ROLE_JSON; do
  [ -z "$ROLE_JSON" ] && continue

  NAME=$(printf '%s' "$ROLE_JSON" | jq -r '.name // empty')
  if [ -z "$NAME" ]; then
    err "active role with no name in roster — skipping"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  RG=$(printf '%s' "$ROLE_JSON" | jq -r '.role_goal // empty')
  [ -z "$RG" ] && RG=".squad/role-goal-$NAME.md"
  RG_PRESENT=false
  [ -f "$RG" ] && RG_PRESENT=true

  SCOPE_JSON=$(printf '%s' "$ROLE_JSON" | jq -c '.file_scope // []')
  FILES=0
  while IFS= read -r G; do
    [ -z "$G" ] && continue
    FILES=$((FILES + $(count_glob "$G")))
  done < <(printf '%s' "$ROLE_JSON" | jq -r '.file_scope[]? // empty')

  jq -nc \
    --arg r "$NAME" --argjson scope "$SCOPE_JSON" \
    --argjson n "$FILES" --argjson rg "$RG_PRESENT" \
    '{role: $r, scope: $scope, files_found: $n, role_goal_present: $rg}'

  ROLE_COUNT=$((ROLE_COUNT + 1))
done <<< "$ROLES_JSON"

# --- Summary -------------------------------------------------------------------

jq -nc \
  --argjson roles "$ROLE_COUNT" \
  --argjson signals "$SIGNAL_COUNT" \
  --argjson errs "$ERRORS" \
  '{summary: true, roles: $roles, signals: $signals, errors: $errs}'

exit 0

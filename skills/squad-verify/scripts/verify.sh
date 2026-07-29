#!/usr/bin/env bash
# verify.sh — Definition-of-done evidence scaffold for cheeky-squad-os.
#
# READ-ONLY. Gathers the mechanical half of verification so the squad-verify
# skill can judge each Definition-of-done signal with evidence in hand:
#   - extracts the goal's "## Definition of done" bullets (signals)
#   - counts deliverable files under each ACTIVE role's file_scope
#   - checks each active role's role-goal file is present
#   - if the role has published its engagement record (hard rule #11,
#     .squad/role-plan-<role>.md), also surfaces: its status, whether its
#     frontmatter role: agrees with the filename, its assumptions by
#     evidence grade, its declared-vs-delivered deliverable gap, and the
#     "if wrong -> " targets named by its [assumed] bullets — so
#     squad-verify can decline to PASS a Definition-of-done signal that
#     rests on the same role's own guess.
#
# It does NOT decide PASS/FAIL — every signal is emitted as "unverified".
# Deciding is the skill's job ("synthesis summarizes; verification decides"),
# with this output as the scaffold. The script never writes any file.
#
# Invoked by the squad-verify skill via Bash, from the PROJECT ROOT (file_scope
# globs and .squad/ paths are project-relative). NOT invoked directly by users.
#
# Inputs (positional):
#   $1 — path to .squad/roster.json (default: .squad/roster.json relative to CWD)
#   $2 — path to .squad/goal.md     (default: .squad/goal.md relative to CWD)
#
# Outputs (stdout, one JSON object per line — easy for the skill to parse):
#   {"signal":"<bullet text>","status":"unverified"}                per DoD signal
#   {"role":"<name>","scope":[…],"files_found":N,"role_goal_present":bool}
#                                                                   per active role
#     — and, ONLY when .squad/role-plan-<name>.md exists (the absence contract:
#       a project with no engagement record anywhere yields the same KEYS as
#       v0.4.x — these are omitted entirely, never emitted as 0 or null):
#       "role_plan_present":true
#       "role_plan_status":"<active|amended|whatever the frontmatter says>"
#       "role_plan_frontmatter_role_match":bool   (false -> filename still wins;
#                                                    also increments `errors`)
#       "role_plan_assumption_grades":{"confirmed":N,"reported":N,"inferred":N,"assumed":N}
#       "role_plan_deliverables_missing":N        (declared in ## Deliverables,
#                                                    not found on disk)
#       "role_plan_assumed_risks":["<if-wrong target>", …]  (one per [assumed]
#                                                    bullet in ## Assumptions)
#   {"summary":true,"roles":N,"signals":N,"errors":K}               final line
#
# One honest exception to that "same keys" claim, and it is a VALUE change, not
# a key change: files_found no longer counts anything under .squad/ (see
# is_squad_path below). A role scoped "**" therefore reports a smaller
# files_found than v0.4.x did, engagement records or not — squad state was
# never that role's work product, and counting it was always wrong.
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

# is_squad_path <rel-path> → returns 0 if <rel-path> IS .squad/ or is nested
# inside it. A prefix test on the resulting path, deliberately not a
# glob-string comparison against the role's declared scope glob — a role
# scoped to "**" (or any broader glob a later release adds) must never have
# .squad/ state re-inflate files_found — including any future squad-state
# subtree, which the prefix test covers for free. Mirrors
# hooks/permission-request.sh's rel_under_squad().
is_squad_path() {
  case "$1" in
    .squad|.squad/*|./.squad|./.squad/*) return 0 ;;
  esac
  return 1
}

# count_glob <glob> → prints the number of regular files the glob covers,
# excluding anything under .squad/ (see is_squad_path above).
# Mirrors the PermissionRequest hook's semantics: "prefix/**" is the whole
# subtree, bare "**" is the whole project (minus .git), and any other glob
# expands with pathname rules where "*" never crosses a "/".
count_glob() {
  local glob="$1" n=0 f
  case "$glob" in
    \*\*)
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        is_squad_path "$f" && continue
        n=$((n + 1))
      done < <(find . -path ./.git -prune -o -type f -print 2>/dev/null)
      ;;
    */\*\*)
      local prefix="${glob%/\*\*}"
      if [ -d "$prefix" ]; then
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          is_squad_path "$f" && continue
          n=$((n + 1))
        done < <(find "$prefix" -type f 2>/dev/null)
      fi
      ;;
    *)
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        is_squad_path "$f" && continue
        n=$((n + 1))
      done < <(compgen -G "$glob" 2>/dev/null || true)
      ;;
  esac
  printf '%s' "$n"
}

# --- Engagement record helpers (hard rule #11) --------------------------------
#
# All of these read .squad/role-plan-<role>.md, per templates/role-plan.md.
# Callers only invoke them once that file's existence has been confirmed —
# the absence contract requires that when it does NOT exist, none of this
# runs and none of these keys are added to the role's output line.

# frontmatter_field <file> <field> → prints the trimmed value of a top-level
# "field: value" line inside the first "---" … "---" fence pair. Empty output
# if the fence or field is missing/malformed — never fatal.
frontmatter_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    BEGIN { fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (!seen) { fm = 1; seen = 1; next }
      else if (fm) { exit }
    }
    fm && $0 ~ "^" field "[[:space:]]*:" {
      line = $0
      sub("^" field "[[:space:]]*:[[:space:]]*", "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      gsub(/^["\x27]+|["\x27]+$/, "", line)
      print line
      exit
    }
  ' "$file" 2>/dev/null
}

# section_lines <file> <heading> → prints the raw body lines of "## <heading>"
# up to the next "## " heading, skipping YAML frontmatter and stripping HTML
# comments (same rules as the DoD-bullet parser above, generalized to any
# heading so it also covers ## Deliverables and ## Assumptions here).
section_lines() {
  local file="$1" heading="$2"
  awk -v heading="$heading" '
    BEGIN { fm = 0; seen_fence = 0; in_comment = 0; in_sec = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_fence) { fm = 1; seen_fence = 1; next }
      else if (fm)     { fm = 0; next }
    }
    fm { next }
    {
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
      hd = $0
      sub(/^##[[:space:]]+/, "", hd)
      sub(/[[:space:]]+$/, "", hd)
      in_sec = (hd == heading) ? 1 : 0
      next
    }
    in_sec { print }
  ' "$file" 2>/dev/null
}

# plan_deliverables_missing <file> → count of ## Deliverables bullets whose
# single backtick-quoted path is NOT present on disk. (No .squad/ exclusion
# here — that requirement names files_found specifically; a role that
# mis-declares a .squad/ path as a deliverable is a declaration problem for
# a human/squad-verify to notice, not something this scaffold should hide.)
plan_deliverables_missing() {
  local file="$1" n=0 path line
  while IFS= read -r line; do
    # shellcheck disable=SC2016 # literal backticks (markdown delimiters), not command substitution
    path=$(printf '%s' "$line" | sed -n 's/.*`\([^`]*\)`.*/\1/p')
    [ -z "$path" ] && continue
    [ -f "$path" ] || n=$((n + 1))
  done < <(section_lines "$file" "Deliverables" | grep -E '^-[[:space:]]+')
  printf '%s' "$n"
}

# plan_assumption_grades <file> → jq object counting ## Assumptions bullets
# by evidence grade: {"confirmed":N,"reported":N,"inferred":N,"assumed":N}.
plan_assumption_grades() {
  local file="$1" content line
  local c=0 r=0 i=0 a=0
  while IFS= read -r line; do
    content=$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')
    case "$content" in
      "[confirmed]"*) c=$((c + 1)) ;;
      "[reported]"*)  r=$((r + 1)) ;;
      "[inferred]"*)  i=$((i + 1)) ;;
      "[assumed]"*)   a=$((a + 1)) ;;
    esac
  done < <(section_lines "$file" "Assumptions" | grep -E '^-[[:space:]]+\[')
  jq -nc --argjson c "$c" --argjson r "$r" --argjson i "$i" --argjson a "$a" \
    '{confirmed: $c, reported: $r, inferred: $i, assumed: $a}'
}

# plan_assumed_risks <file> → jq array of the "if wrong -> <target>" clause
# text from every [assumed] bullet in ## Assumptions (accepts the unicode
# "→" the template ships, or an ASCII "->"). A bullet with no such clause
# contributes nothing — squad-verify judges completeness, this only reports.
plan_assumed_risks() {
  local file="$1" content line target
  local -a risks=()
  while IFS= read -r line; do
    content=$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')
    case "$content" in
      "[assumed]"*)
        # Two separate patterns, not a \|-alternation: BSD sed (macOS) has
        # no BRE alternation, so try the template's unicode arrow first,
        # then fall back to an ASCII "->".
        target=$(printf '%s' "$content" \
          | sed -n 's/.*if wrong[[:space:]]*→[[:space:]]*//p')
        if [ -z "$target" ]; then
          target=$(printf '%s' "$content" \
            | sed -n 's/.*if wrong[[:space:]]*->[[:space:]]*//p')
        fi
        [ -n "$target" ] && risks+=("$target")
        ;;
    esac
  done < <(section_lines "$file" "Assumptions" | grep -E '^-[[:space:]]+\[')
  if [ "${#risks[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${risks[@]}" | jq -R . | jq -sc .
  fi
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

  # --- Engagement record (hard rule #11) — absence contract in force ---------
  # PLAN is looked up by the roster's own role name, i.e. by the FILENAME this
  # role is entitled to publish (hooks/permission-request.sh grants exactly
  # .squad/role-plan-<agent_type>.md). If the file is absent, no plan_* key is
  # added below at all — the role's line stays byte-identical to v0.4.x.
  PLAN_FILE=".squad/role-plan-$NAME.md"
  if [ -f "$PLAN_FILE" ]; then
    PLAN_STATUS=$(frontmatter_field "$PLAN_FILE" "status")
    PLAN_ROLE=$(frontmatter_field "$PLAN_FILE" "role")

    # The filename ($NAME) wins on any mismatch — the record is still
    # attributed to $NAME below. A mismatch is a squad-authoring defect, so
    # it feeds the same error counter as every other roster/record problem.
    PLAN_ROLE_MATCH=true
    if [ -n "$PLAN_ROLE" ] && [ "$PLAN_ROLE" != "$NAME" ]; then
      PLAN_ROLE_MATCH=false
      ERRORS=$((ERRORS + 1))
    fi

    PLAN_GRADES=$(plan_assumption_grades "$PLAN_FILE")
    PLAN_DELIV_MISSING=$(plan_deliverables_missing "$PLAN_FILE")
    PLAN_RISKS=$(plan_assumed_risks "$PLAN_FILE")

    jq -nc \
      --arg r "$NAME" --argjson scope "$SCOPE_JSON" \
      --argjson n "$FILES" --argjson rg "$RG_PRESENT" \
      --arg pstatus "$PLAN_STATUS" \
      --argjson pmatch "$PLAN_ROLE_MATCH" \
      --argjson pgrades "$PLAN_GRADES" \
      --argjson pmissing "$PLAN_DELIV_MISSING" \
      --argjson prisks "$PLAN_RISKS" \
      '{role: $r, scope: $scope, files_found: $n, role_goal_present: $rg,
        role_plan_present: true,
        role_plan_status: $pstatus,
        role_plan_frontmatter_role_match: $pmatch,
        role_plan_assumption_grades: $pgrades,
        role_plan_deliverables_missing: $pmissing,
        role_plan_assumed_risks: $prisks}'
  else
    jq -nc \
      --arg r "$NAME" --argjson scope "$SCOPE_JSON" \
      --argjson n "$FILES" --argjson rg "$RG_PRESENT" \
      '{role: $r, scope: $scope, files_found: $n, role_goal_present: $rg}'
  fi

  ROLE_COUNT=$((ROLE_COUNT + 1))
done <<< "$ROLES_JSON"

# --- Summary -------------------------------------------------------------------

jq -nc \
  --argjson roles "$ROLE_COUNT" \
  --argjson signals "$SIGNAL_COUNT" \
  --argjson errs "$ERRORS" \
  '{summary: true, roles: $roles, signals: $signals, errors: $errs}'

exit 0

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
#       "role_plan_status":"<active|amended|escalated|whatever the frontmatter says>"
#       "role_plan_frontmatter_role_match":bool   (false -> filename still wins;
#                                                    also increments `errors`)
#       "role_plan_assumption_grades":{"confirmed":N,"reported":N,"inferred":N,"assumed":N}
#       "role_plan_deliverables_missing":N        (declared in ## Deliverables,
#                                                    not found on disk)
#       "role_plan_assumed_risks":["<if-wrong target>", …]  (one per [assumed]
#                                                    bullet in ## Assumptions)
#       "role_plan_fired":"<verbatim>"            (frontmatter "fired:" —
#                                                    empty string unless the
#                                                    record is escalated)
#       "role_plan_hand_back_sections_present":{"what_happened":bool,
#         "state_of_work":bool,"what_would_unblock":bool}   (the three
#         "escalated only" sections in templates/role-plan.md — hard rule
#         #14; present means the heading exists AND has non-blank body once
#         comments are stripped, not just a bare heading)
#   {"summary":true,"roles":N,"signals":N,"errors":K}               final line,
#     PLUS "escalations_open":N — but ONLY once at least one engagement
#     record exists anywhere in this run (the absence contract again: a
#     squad that never used #11/#14 produces this exact summary shape with
#     no escalation key at all, not 0, not null).
#     PLUS "world_conflicts":C — but ONLY when .squad/world/ exists at all
#     (the belief ledger, hard rule #13; independent absence condition from
#     escalations_open above — a squad can have one feature and not the
#     other). Omitted entirely, not 0, not null, when .squad/world/ is
#     absent; present as a real count, including 0, the moment the directory
#     exists — see "World-model conflicts" below.
#
# World-model conflicts (hard rule #13) — a SEPARATE, independent absence
# condition from escalations_open above:
#   world_conflicts = |belief keys with >=2 valid, live blocks from
#                       DIFFERENT owners' .squad/world/claims-*.md files|
# computed by re-parsing every claims file directly, read-only, the same
# jq/awk pattern this script already uses — NOT by shelling out to
# skills/squad-world/scripts/world.sh (a different skill's script; this
# script stays self-contained, per its own header). A block missing
# Claim/Source/Grade/Observed, carrying an off-vocabulary Grade or Status,
# or duplicated as `live` twice within one owner's OWN file, is invalid and
# excluded here exactly as hard rule #13 requires it be excluded from every
# prompt. A trailing HTML comment is stripped from every field value before
# any of that is judged — templates/world-claims.md's own annotations make
# that the difference between a belief and a silent no-op. Any drift between
# this and world.sh's own notion of "valid" is a defect to fix in both
# scripts, not a reason to couple them.
#
# THE LOAD-BEARING COMPUTATION (hard rule #14/#15, FIX-1) — a role can never
# mint the human's ruling. escalations_open is computed from two inputs
# neither of which a role controls:
#   escalations_open = |records with status: escalated|
#                     - |their roles named in .squad/verification.md's
#                        resolved_escalations|
# by SET DIFFERENCE on role names (not a raw count subtraction) — a role
# named in resolved_escalations that is not, or is no longer, escalated
# must never push the count negative. verification.md is squad-verify-owned
# and structurally unwritable by any role (the .squad/ reservation, v0.4.1
# / FIX-2), so this subtraction cannot be forged from inside a role's own
# invocation. Residual, stated honestly: a role CAN flip its own record's
# status back from escalated to active — that is behaviorally identical to
# never having stopped, the already-acknowledged aspirational half of #14.
# What a role cannot do is manufacture the human's ruling that closes one.
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

# .squad/verification.md — squad-verify-owned, structurally unwritable by any
# role (the .squad/ reservation). Not a positional parameter: every other
# .squad/ path in this script (role-plan files below) is hardcoded relative
# to the project root the same way, per the established convention.
VERIFICATION=".squad/verification.md"

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

# --- Escalation & the evidence bar (hard rules #14-#15) ------------------------
#
# section_has_content <file> <heading> → prints "true"/"false". "Present"
# means the heading exists AND has non-blank body content once frontmatter
# and HTML comments are stripped (section_lines) — a bare heading left
# exactly as the template ships it (comment-only) counts as NOT present. A
# role that escalates without actually saying what happened has handed
# nothing real back.
section_has_content() {
  local file="$1" heading="$2" body
  body=$(section_lines "$file" "$heading" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^[[:space:]]*$' || true)
  if [ -n "$body" ]; then printf 'true'; else printf 'false'; fi
}

# resolved_escalation_roles <file> → prints one role name per line, read from
# the frontmatter "resolved_escalations:" YAML list (FIX-1). This is the
# ONLY place a human's ruling reaches this script, and the file it reads is
# structurally unwritable by any role (the .squad/ reservation).
#
# Accepts EITHER YAML shape a squad-verify run could produce:
#   block style   resolved_escalations:\n  - roleA\n  - roleB
#   flow style    resolved_escalations: [roleA, roleB]   (incl. bare `[]`)
# Block style is canonical (templates/verification.md, and the worked example
# in examples/klaviyo-audit.md); flow style is parsed too so a real resolution
# is never missed on a format guess. Block-style dashes are matched with
# OPTIONAL leading indentation — the canonical YAML spelling indents them two
# spaces, and a parser that only accepted a column-0 dash silently ignored a
# ruling a human had actually recorded, leaving escalations_open permanently
# above zero and `met` unreachable.
#
# Never fatal: a missing file, a missing key, or a malformed / partially-
# written file (no closing fence, garbage body, whatever) all degrade to
# "nothing resolved" — empty output — rather than erroring. That is what
# keeps a parse failure from silently ZEROING the open count: an empty
# resolved list subtracts nothing, so the full escalated count stands
# rather than being (wrongly) driven to 0.
resolved_escalation_roles() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { fm = 0; seen_fence = 0; in_key = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_fence) { fm = 1; seen_fence = 1; next }
      else if (fm)     { exit }
    }
    fm {
      if ($0 ~ /^resolved_escalations:/) {
        line = $0
        sub(/^resolved_escalations:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line == "") { in_key = 1; next }
        if (line ~ /^\[.*\]$/) {
          inner = substr(line, 2, length(line) - 2)
          n = split(inner, items, ",")
          for (i = 1; i <= n; i++) {
            item = items[i]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
            gsub(/^["\x27]+|["\x27]+$/, "", item)
            if (item != "") print item
          }
        }
        in_key = 0
        next
      }
      if (in_key) {
        if ($0 ~ /^[[:space:]]*-[[:space:]]+[^[:space:]]/) {
          line = $0
          sub(/^[[:space:]]*-[[:space:]]+/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          sub(/[[:space:]]+$/, "", line)
          gsub(/^["\x27]+|["\x27]+$/, "", line)
          if (line != "") print line
          next
        }
        in_key = 0
      }
    }
  ' "$file" 2>/dev/null || true
}

ROLE_COUNT=0
ROLE_PLAN_COUNT=0        # roles with a published engagement record, any status
ESCALATED_LIST=()        # filenames (role names) whose record's status is "escalated"
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

    # Escalation half of the schema (hard rule #14) — computed for every
    # published record, not only escalated ones, so the per-role shape
    # stays stable regardless of status (same discipline as the fields
    # above): an active/amended record simply reports an empty "fired" and
    # all-false sections.
    PLAN_FIRED=$(frontmatter_field "$PLAN_FILE" "fired")
    PLAN_WH=$(section_has_content "$PLAN_FILE" "What happened")
    PLAN_SW=$(section_has_content "$PLAN_FILE" "State of the work")
    PLAN_WU=$(section_has_content "$PLAN_FILE" "What would unblock")
    PLAN_SECTIONS=$(jq -nc \
      --argjson wh "$PLAN_WH" --argjson sw "$PLAN_SW" --argjson wu "$PLAN_WU" \
      '{what_happened: $wh, state_of_work: $sw, what_would_unblock: $wu}')

    ROLE_PLAN_COUNT=$((ROLE_PLAN_COUNT + 1))
    # Filename wins (same rule PLAN_ROLE_MATCH already enforces above): this
    # record is attributed to $NAME for the open-escalation count too, never
    # to whatever the frontmatter "role:" happens to say.
    if [ "$PLAN_STATUS" = "escalated" ]; then
      ESCALATED_LIST+=("$NAME")
    fi

    jq -nc \
      --arg r "$NAME" --argjson scope "$SCOPE_JSON" \
      --argjson n "$FILES" --argjson rg "$RG_PRESENT" \
      --arg pstatus "$PLAN_STATUS" \
      --argjson pmatch "$PLAN_ROLE_MATCH" \
      --argjson pgrades "$PLAN_GRADES" \
      --argjson pmissing "$PLAN_DELIV_MISSING" \
      --argjson prisks "$PLAN_RISKS" \
      --arg pfired "$PLAN_FIRED" \
      --argjson psections "$PLAN_SECTIONS" \
      '{role: $r, scope: $scope, files_found: $n, role_goal_present: $rg,
        role_plan_present: true,
        role_plan_status: $pstatus,
        role_plan_frontmatter_role_match: $pmatch,
        role_plan_assumption_grades: $pgrades,
        role_plan_deliverables_missing: $pmissing,
        role_plan_assumed_risks: $prisks,
        role_plan_fired: $pfired,
        role_plan_hand_back_sections_present: $psections}'
  else
    jq -nc \
      --arg r "$NAME" --argjson scope "$SCOPE_JSON" \
      --argjson n "$FILES" --argjson rg "$RG_PRESENT" \
      '{role: $r, scope: $scope, files_found: $n, role_goal_present: $rg}'
  fi

  ROLE_COUNT=$((ROLE_COUNT + 1))
done <<< "$ROLES_JSON"

# --- Escalations open (hard rule #14/#15, FIX-1) --------------------------------
#
# escalations_open = |escalated roles| - |those roles named in
# verification.md's resolved_escalations| — a SET DIFFERENCE, computed only
# once at least one engagement record exists anywhere (ROLE_PLAN_COUNT > 0).
# Neither input is role-controlled: the escalated set comes from records
# this script has already read above, keyed by filename; the resolved set
# comes from .squad/verification.md, which no role can write.

ESCALATIONS_OPEN=0
if [ "$ROLE_PLAN_COUNT" -gt 0 ]; then
  RESOLVED=$(resolved_escalation_roles "$VERIFICATION")
  if [ "${#ESCALATED_LIST[@]}" -gt 0 ]; then
    for ESC_ROLE in "${ESCALATED_LIST[@]}"; do
      if ! grep -Fxq "$ESC_ROLE" <<< "$RESOLVED" 2>/dev/null; then
        ESCALATIONS_OPEN=$((ESCALATIONS_OPEN + 1))
      fi
    done
  fi
fi

# --- World-model conflicts (hard rule #13) --------------------------------
#
# Independent absence condition from escalations_open: gated only on
# .squad/world/ existing, nothing to do with engagement records. A block
# invalid by the SAME four-field rule hard rule #13 states (missing
# Claim/Source/Grade/Observed, or an off-vocabulary Grade) is excluded, as
# is a key duplicated `live` twice within one owner's own file (a
# self-contradiction, not a cross-owner dispute). Only a key with >=2
# valid `live` blocks from DIFFERENT owner files counts as a conflict.

WORLD_DIR=".squad/world"
WORLD_CONFLICTS=""   # unset string = omit the field entirely (dir absent)

# parse_claims_file <file> → one TSV line per "## Belief: <key>" block found:
#   valid|invalid<TAB>key<TAB>status
# status defaults to "live" when the block has no Status: line (the belief
# block schema's stated default — templates/world-claims.md).
parse_claims_file() {
  awk '
    # fieldval(<line>, <label>) → the field value with the label, any
    # trailing HTML comment, and surrounding whitespace removed. The comment
    # strip is load-bearing and matches world.sh exactly: templates/
    # world-claims.md annotates its own Status: line inline, so a block
    # copied from the template read as status "live <!-- … -->" — not
    # "live", so it silently never projected and never showed as invalid
    # either, since no field was actually missing.
    function fieldval(line, label,   v) {
      v = line
      sub("^" label ":[[:space:]]*", "", v)
      sub(/[[:space:]]*<!--.*$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      return v
    }
    function flush() {
      if (key != "") {
        ok = (has_claim && has_source && has_observed && grade_ok && status_ok)
        print (ok ? "valid" : "invalid") "\t" key "\t" status
      }
    }
    BEGIN { key = ""; has_claim = 0; has_source = 0; has_observed = 0
            grade_ok = 0; status = "live"; status_ok = 1 }
    /^##[[:space:]]+Belief:[[:space:]]*/ {
      flush()
      key = $0
      sub(/^##[[:space:]]+Belief:[[:space:]]*/, "", key)
      sub(/[[:space:]]*<!--.*$/, "", key)
      sub(/[[:space:]]+$/, "", key)
      has_claim = 0; has_source = 0; has_observed = 0
      grade_ok = 0; status = "live"; status_ok = 1
      next
    }
    # A block ends at the next markdown heading of ANY level, not only the
    # next "## Belief:" — a field line under an unrelated heading is outside
    # the block and must not complete it. world.sh applies the same rule.
    /^#+[[:space:]]/ { flush(); key = ""; next }
    key == "" { next }
    /^Claim:/    { has_claim    = (fieldval($0, "Claim")    != "") }
    /^Source:/   { has_source   = (fieldval($0, "Source")   != "") }
    /^Observed:/ { has_observed = (fieldval($0, "Observed") != "") }
    /^Grade:/ {
      g = fieldval($0, "Grade")
      grade_ok = (g == "confirmed" || g == "reported" || g == "inferred" || g == "assumed")
    }
    # An off-vocabulary Status is INVALID, not silently non-live — same rule
    # world.sh applies, for the same reason: a block that is neither
    # projected nor reported has quietly stopped existing, taking any
    # dispute it was party to with it.
    /^Status:/ {
      s = fieldval($0, "Status")
      if (s != "") status = s
      status_ok = (status == "live" || status == "superseded" || status == "retired")
    }
    END { flush() }
  ' "$1" 2>/dev/null
}

# claims_live_keys <file> <owner> → one "key<TAB>owner" line per valid,
# live belief in <file>, EXCLUDING any key that appears as valid+live more
# than once within this SAME file (duplicate live key within one owner's
# own file → invalid, per hard rule #13 — self-contradiction, not a
# cross-owner dispute; neither instance counts).
#
# ORDER IS LOAD-BEARING and matches world.sh's: the duplicate filter runs
# over blocks that ALREADY passed field validation ($1 == "valid"), never
# over raw parse output. A malformed sibling under the same key must not
# drag a well-formed belief down with it — doing so would also hide the
# cross-owner conflict that belief is party to, which is the one number
# this whole section exists to compute.
claims_live_keys() {
  local file="$1" owner="$2" parsed dup_keys
  parsed=$(parse_claims_file "$file")
  [ -z "$parsed" ] && return 0

  dup_keys=$(printf '%s\n' "$parsed" \
    | awk -F'\t' '$1 == "valid" && $3 == "live" { print $2 }' \
    | sort | uniq -d)

  local valid key status
  while IFS=$'\t' read -r valid key status; do
    [ -z "$key" ] && continue
    [ "$valid" = "valid" ] && [ "$status" = "live" ] || continue
    if [ -n "$dup_keys" ] && printf '%s\n' "$dup_keys" | grep -Fxq "$key"; then
      continue
    fi
    printf '%s\t%s\n' "$key" "$owner"
  done <<< "$parsed"
}

if [ -d "$WORLD_DIR" ]; then
  ALL_LIVE=""
  while IFS= read -r CFILE; do
    [ -z "$CFILE" ] && continue
    CBASE=$(basename "$CFILE")
    case "$CBASE" in
      claims-*.md)
        COWNER="${CBASE#claims-}"
        COWNER="${COWNER%.md}"
        ;;
      *) continue ;;  # not a claims file — ignore any stray file under world/
    esac
    ENTRY=$(claims_live_keys "$CFILE" "$COWNER")
    if [ -n "$ENTRY" ]; then
      if [ -n "$ALL_LIVE" ]; then
        ALL_LIVE="$ALL_LIVE
$ENTRY"
      else
        ALL_LIVE="$ENTRY"
      fi
    fi
  done < <(find "$WORLD_DIR" -maxdepth 1 -type f -name 'claims-*.md' 2>/dev/null)

  if [ -n "$ALL_LIVE" ]; then
    WORLD_CONFLICTS=$(printf '%s\n' "$ALL_LIVE" \
      | sort -u \
      | awk -F'\t' '{print $1}' \
      | sort | uniq -c \
      | awk '$1 >= 2' | wc -l | tr -d '[:space:]')
  else
    WORLD_CONFLICTS=0
  fi
fi

# --- Summary -------------------------------------------------------------------

JQ_ARGS=(--argjson roles "$ROLE_COUNT" --argjson signals "$SIGNAL_COUNT" --argjson errs "$ERRORS")
# shellcheck disable=SC2016 # jq filter syntax ($roles etc. are jq --argjson
# names, resolved by jq itself — not shell variables, must stay single-quoted
JQ_FILTER='{summary: true, roles: $roles, signals: $signals, errors: $errs}'

if [ "$ROLE_PLAN_COUNT" -gt 0 ]; then
  JQ_ARGS+=(--argjson open "$ESCALATIONS_OPEN")
  # shellcheck disable=SC2016 # jq filter syntax, see above
  JQ_FILTER="$JQ_FILTER"' + {escalations_open: $open}'
fi

if [ -n "$WORLD_CONFLICTS" ]; then
  JQ_ARGS+=(--argjson wc "$WORLD_CONFLICTS")
  # shellcheck disable=SC2016 # jq filter syntax, see above
  JQ_FILTER="$JQ_FILTER"' + {world_conflicts: $wc}'
fi

jq -nc "${JQ_ARGS[@]}" "$JQ_FILTER"

exit 0

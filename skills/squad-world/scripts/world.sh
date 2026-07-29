#!/usr/bin/env bash
# world.sh — the shared world model's belief-ledger parser (hard rule #13).
#
# READ-ONLY. Parses every .squad/world/claims-<owner>.md in the project,
# validates each belief block, detects cross-owner conflicts, and either
# dumps the parsed result as JSON lines or projects it into the literal text
# a spawn prompt pastes in verbatim. It never writes any file.
#
# Invoked from the PROJECT ROOT (mirrors skills/squad-verify/scripts/verify.sh
# — .squad/world/ is resolved project-relative, no positional arguments name
# it). NOT invoked directly by users; the squad-world skill shells out to it.
#
# --------------------------------------------------------------------------
# HARD RULE #13 — "a belief with no source is a rumor." This script IS the
# mechanical guarantee, not a request roles are expected to honor:
#
#   A belief block is INVALID — and excluded from every projection, full
#   stop — when any of these hold:
#     - Claim, Source, Grade, or Observed is missing (blank/absent)
#     - Grade is not one of: confirmed | reported | inferred | assumed
#       (the SAME four-grade vocabulary as templates/role-plan.md — one
#       vocabulary across the plugin, never invented twice, never numbers)
#     - Status is present but not one of: live | superseded | retired
#       (absent defaults to live). An off-vocabulary status is REPORTED,
#       never silently treated as not-live — a block that is neither
#       projected nor reported has quietly stopped existing, and takes any
#       dispute it was party to down with it.
#     - its key is duplicated by another FIELD-VALID `live`-status block IN
#       THE SAME FILE (same owner asserting two different live beliefs under
#       one key is a self-contradiction the parser refuses to arbitrate)
#     - owner is `research` (derived from the filename claims-research.md,
#       positionally — see below) AND Grade is `inferred` or `assumed`
#       (reason: research_grade_ceiling — see THE RESEARCH GRADE CEILING,
#       below)
#
# ORDER IS LOAD-BEARING: the duplicate check runs AFTER field validation,
# over the survivors only. Running it first meant a malformed sibling block
# under the same key dragged a perfectly good belief down with it — and,
# worse, that suppressed belief then could not be seen to conflict with
# another owner's, so a REAL cross-owner dispute went unreported. Two blocks
# under one key where only one is field-valid is not a self-contradiction;
# the owner is asserting exactly one thing and fumbling a second write.
# skills/squad-verify/scripts/verify.sh's independent re-derivation of
# world_conflicts applies the same order, deliberately.
#
# THE RESEARCH GRADE CEILING — a per-owner grade ceiling, and the ONE
# deliberate research fingerprint in shipped script code (owner-approved
# explicitly, over the alternative of a sentence in a skill body: guarding
# the plugin's single most tempting rumor path with an instruction is
# exactly what this repo says it does not do).
#
#   In claims-research.md — and ONLY there, matched by owner == "research"
#   as derived positionally from the filename above, the SAME derivation
#   every other owner check in this script uses — a field-valid block whose
#   Grade is `inferred` or `assumed` is INVALID, with reason
#   `research_grade_ceiling`, distinct from `bad_grade` on purpose: the
#   grade IS on-vocabulary, it is simply too weak a grade for this owner.
#   Research may produce only `confirmed` or `reported`.
#
#   This is not a general per-owner policy engine — it is one hard-coded
#   comparison against the literal string "research". No other owner is
#   affected: claims-user.md has no ceiling at all (the human may assert an
#   inference; that is their prerogative and their name is on it), and
#   every ordinary role's claims-<role>.md is unaffected — an engagement's
#   own `inferred`/`assumed` claims about its own work are exactly what
#   templates/role-plan.md's Assumptions vocabulary is for.
#
#   Checked in Pass 1 (field validation), alongside the vocabulary check —
#   NOT a separate pass, and it never touches the duplicate-live-key order
#   documented above: a ceiling-rejected block is already excluded before
#   Pass 2 runs, so it can never masquerade as a live duplicate.
#
# A BLOCK ENDS AT THE NEXT MARKDOWN HEADING of any level, not only at the
# next "## Belief:". A field line sitting under some other heading is
# outside the block and does not satisfy it — otherwise a block missing
# Observed could be completed by an "Observed:" line further down the file
# under an unrelated heading, and a rumor would reach a prompt through the
# side door.
#
# `superseded` and `retired` blocks are parsed (they still appear as
# "belief" lines below, for audit) but are NEVER projected — not into the
# default JSON dump's "live" count, and never into --index output.
#
# TWO LIVE BLOCKS UNDER ONE KEY, FROM DIFFERENT OWNERS, ARE NOT INVALID —
# they are a CONFLICT ("disputed"). Both are individually well-formed; the
# system just now knows two roles believe different things. `disputed` is
# derived here, purely from this detection — nothing ever writes the word
# by hand, and nothing here resolves it. The human adjudicates, always
# (hard rule #10's spirit) — this script only ever surfaces the conflict.
#
# DELIBERATE NON-GOALS (state them plainly; do not silently half-build them):
#   - No TTL / no staleness decay. A belief does not rot on a timer.
#   - No semantic contradiction detection. Only IDENTICALLY KEYED live
#     blocks are ever compared. Two owners can contradict each other in
#     different words under different keys and this script will not notice.
#   - No auto-resolution, ever. Not latest-wins, not "more confirmed wins",
#     nothing. A conflict line just names every claimant.
#   - No cross-squad merge. A parked squad's world/ is its own.
#   - Grades are self-reported. Nothing here can verify a Source: line
#     tells the truth — this script checks the field is PRESENT and
#     on-vocabulary, never that it is honest.
#
# --------------------------------------------------------------------------
# MODE (a) — default: emit JSON lines, one per belief / invalid block /
# conflict, plus a summary line last (mirrors verify.sh's shape: the line's
# distinguishing key holds the meaningful value, same trick as verify.sh's
# "signal"/"role"/"summary"):
#
#   {"belief":"<key>","owner":"<owner>","claim":"…","source":"…",
#    "grade":"…","observed":"…","status":"live|superseded|retired",
#    "notes":"…"}                                  one per VALID block
#   {"invalid":"<key>","owner":"<owner>","file":"<path>",
#    "reasons":["missing_source", …]}               one per INVALID block
#      reasons ⊂ {missing_claim, missing_source, missing_grade,
#                 missing_observed, bad_grade, bad_status,
#                 duplicate_live_key, research_grade_ceiling}
#   {"conflict":"<key>","owners":["a","b", …]}       one per disputed key
#   {"summary":true,"files":N,"beliefs":N,"live":N,"invalid":N,
#    "conflicts":N}                                  final line, always last
#
# MODE (b) — `--index [--cap N] [--disputed-cap M]`: performs the
# projection ITSELF and prints the literal text a spawn prompt pastes in
# verbatim — never LLM-assembled prose, which is what makes the token
# budget a bats-defensible claim rather than a hope:
#
#   ## World model
#   - <key>: <claim> — <owner> [<grade>, observed <date>]   (recency-ordered,
#   - …                                                       80-byte
#   +<N> more on disk                        (only if beyond --cap, default 50)
#
#   ## Disputed                       (only if at least one disputed key exists)
#   ### <key>
#   - [<owner>] <grade> · <source> · observed <date>: <claim>   (full, untruncated,
#   - [<owner>] …                                                 one per claimant)
#   +<K> more disputed — run squad-world   (only if beyond --disputed-cap, default 5)
#
#   Invalid: <N> (excluded from every projection)     always last, own line
#
# Disputed keys are shown ONLY as full claimant blocks, never also as a
# truncated index line — the whole point of a conflict is that a one-line
# summary would hide it.
#
# --------------------------------------------------------------------------
# ABSENCE CONTRACT — a squad with no .squad/world/, or one whose claims
# files hold no parseable "## Belief:" block at all, emits NOTHING AT ALL —
# not even the summary line, in either mode. This is what lets a squad that
# never uses the feature behave byte-identically to one that predates it:
# no world_conflicts field in verification.md, no world section in spawn
# prompts, byte-identical SessionStart.
#
# --index carries ONE ADDITIONAL silence condition the default mode does
# NOT: zero valid LIVE beliefs also emits nothing, because a prompt has
# nothing to be told. The default mode deliberately keeps talking there —
# it is the human's inspection surface, and a ledger whose every block is
# invalid is exactly the case where silence would be the worst possible
# answer: the beliefs vanish from every prompt and nothing anywhere says
# why. Invalid lines and the summary still print; the projection stays
# empty. Silence toward a prompt, never toward the human.
#
# --------------------------------------------------------------------------
# OWNERSHIP IS POSITIONAL, BY FILENAME — `.squad/world/claims-<owner>.md`
# names its own owner; nothing inside the file can override it. This
# script does not re-enforce who may WRITE which file — that is
# hooks/permission-request.sh's job (squad_grant, including the refusal of
# the reserved owner names `user` and `research`), already shipped and out
# of scope here. This script only ever READS whatever files exist.
#
# Errors go to stderr. Exit 0 in every case except a missing jq (exit 1) —
# a read-only projection tool has nothing that should ever hard-fail on
# malformed input; a malformed block becomes an "invalid" line, not a crash.

set -u  # no -e: a partial parse beats a dead one — a malformed block
        # degrades to "invalid", it never aborts the run.

# Byte collation for every comparison, sort, and slice below — same reason
# hooks/permission-request.sh pins it. A projection whose contents change
# with the runner's locale is not a bats-defensible token budget, and
# ${#line} / ${line:0:n} are exactly the operations that silently switch
# between characters and bytes on it. Here they are always bytes; the
# 80-byte cap is enforced by truncate_line below, which never leaves a
# UTF-8 sequence half-cut.
LC_ALL=C
export LC_ALL

err() { echo "world.sh: $*" >&2; }

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed. Install with: brew install jq (macOS) / apt-get install jq (Linux)"
  exit 1
fi

# --- Argument parsing ---------------------------------------------------------

MODE="default"
CAP=50
DISPUTED_CAP=5

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --index)
      MODE="index"
      shift
      ;;
    --cap)
      is_uint "${2:-}" && CAP="$2"
      shift 2 2>/dev/null || shift $#
      ;;
    --disputed-cap)
      is_uint "${2:-}" && DISPUTED_CAP="$2"
      shift 2 2>/dev/null || shift $#
      ;;
    *)
      # Unrecognized argument — this is a read-only reporting tool, not a
      # gate; ignore rather than fail the whole run over an option typo.
      shift
      ;;
  esac
done

WORLD_DIR=".squad/world"

# --- Absence contract, part 1: no directory at all → emit nothing ------------

if [ ! -d "$WORLD_DIR" ]; then
  exit 0
fi

# --- Temp workspace ------------------------------------------------------------

TMPDIR_WORLD=$(mktemp -d 2>/dev/null) || exit 0
trap 'rm -rf "$TMPDIR_WORLD"' EXIT

NORM_RECORDS="$TMPDIR_WORLD/norm.tsv"        # owner\037file\037key\037claim\037source\037grade\037observed\037status\037notes
VALID_RECORDS="$TMPDIR_WORLD/valid.tsv"      # same 9-column shape, validated blocks only
INVALID_RECORDS="$TMPDIR_WORLD/invalid.tsv"  # owner\037file\037key\037reasons(csv)
LIVE_RECORDS="$TMPDIR_WORLD/live.tsv"        # VALID_RECORDS filtered to status=="live"
DUP_KEYS="$TMPDIR_WORLD/dup.tsv"             # owner\037key pairs duplicated (live, same file)
KEY_OWNER_PAIRS="$TMPDIR_WORLD/key_owner.tsv"
DISPUTED_KEYS="$TMPDIR_WORLD/disputed.tsv"   # one key per line, sorted
: > "$NORM_RECORDS"
: > "$VALID_RECORDS"
: > "$INVALID_RECORDS"

US=$'\037'  # unit separator — never appears in prose, safe as a field delimiter

# --- Parse: one file → one record per "## Belief:" block ---------------------
#
# Fields collected verbatim (trimmed), in file order. A block whose heading
# has no key text after "## Belief:" is silently dropped — there is no key
# to report it under, so it can be neither a belief nor an invalid line.
#
# A block ends at the next markdown heading of ANY level (the second rule
# below), not only at the next "## Belief:". Without that, a field line
# under an unrelated heading later in the file was absorbed into the
# preceding block, and a block missing a required field could be silently
# completed from outside itself — a rumor reaching a prompt through the
# side door. verify.sh's parse_claims_file() terminates on the same rule.
parse_file() {
  awk '
    # A trailing HTML comment is not part of a field value. templates/
    # world-claims.md annotates its own Status: line that way, so a block
    # copied from the template carried the comment into the value: the
    # status read as "live <!-- … -->", which is not "live", so the belief
    # silently never projected AND never showed up as invalid (no field
    # was missing) — the worst possible failure shape for this feature.
    # Stripped here for every field, and identically in verify.sh.
    function trim(s) {
      sub(/[[:space:]]*<!--.*$/, "", s)
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    function emit() {
      if (have) {
        printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", key, claim, source, grade, observed, status, notes
      }
    }
    BEGIN { have = 0 }
    /^##[ \t]+Belief:/ {
      emit()
      key = $0
      sub(/^##[ \t]+Belief:/, "", key)
      key = trim(key)
      claim = ""; source = ""; grade = ""; observed = ""; status = ""; notes = ""
      have = (key != "") ? 1 : 0
      next
    }
    /^#+[ \t]/ { emit(); have = 0; next }
    have && /^Claim:/    { v = $0; sub(/^Claim:/, "", v);    claim    = trim(v); next }
    have && /^Source:/   { v = $0; sub(/^Source:/, "", v);   source   = trim(v); next }
    have && /^Grade:/    { v = $0; sub(/^Grade:/, "", v);    grade    = trim(v); next }
    have && /^Observed:/ { v = $0; sub(/^Observed:/, "", v); observed = trim(v); next }
    have && /^Status:/   { v = $0; sub(/^Status:/, "", v);   status   = trim(v); next }
    have && /^Notes:/    { v = $0; sub(/^Notes:/, "", v);    notes    = trim(v); next }
    END { emit() }
  ' "$1" 2>/dev/null
}

FILES=0
while IFS= read -r cf; do
  [ -z "$cf" ] && continue
  base=$(basename "$cf")
  owner="${base#claims-}"
  owner="${owner%.md}"
  [ -z "$owner" ] && continue   # "claims-.md" or similar — no owner to attribute it to
  FILES=$((FILES + 1))
  while IFS="$US" read -r key claim source grade observed status notes; do
    [ -z "$key" ] && continue
    [ -z "$status" ] && status="live"   # Status is the one optional field — default live
    printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
      "$owner" "$cf" "$key" "$claim" "$source" "$grade" "$observed" "$status" "$notes" \
      >> "$NORM_RECORDS"
  done < <(parse_file "$cf")
done < <(find "$WORLD_DIR" -maxdepth 1 -type f -name 'claims-*.md' 2>/dev/null | sort)

# --- Pass 1: field validation (hard rule #13's teeth) --------------------------
#
# The four required fields and the grade vocabulary. The duplicate-live-key
# rule is deliberately NOT applied here — see pass 2 and the header note on
# why the order is load-bearing.

FIELD_VALID="$TMPDIR_WORLD/field_valid.tsv"
: > "$FIELD_VALID"

while IFS="$US" read -r owner cf key claim source grade observed status notes; do
  reasons=""
  [ -z "$claim" ]    && reasons="${reasons:+$reasons,}missing_claim"
  [ -z "$source" ]   && reasons="${reasons:+$reasons,}missing_source"
  [ -z "$grade" ]    && reasons="${reasons:+$reasons,}missing_grade"
  [ -z "$observed" ] && reasons="${reasons:+$reasons,}missing_observed"
  if [ -n "$grade" ]; then
    case "$grade" in
      confirmed|reported|inferred|assumed) ;;
      *) reasons="${reasons:+$reasons,}bad_grade" ;;
    esac
    # THE RESEARCH GRADE CEILING (see header) — owner "research", derived
    # positionally from claims-research.md, may assert only confirmed or
    # reported. On-vocabulary but too weak a grade for this one owner gets
    # its own reason, distinct from bad_grade, so squad-world's inspect
    # can tell a human WHY a research finding was rejected, not just THAT
    # it was.
    if [ "$owner" = "research" ]; then
      case "$grade" in
        inferred|assumed) reasons="${reasons:+$reasons,}research_grade_ceiling" ;;
      esac
    fi
  fi
  # An off-vocabulary Status is INVALID, not silently non-live. Left to fall
  # through, a typo'd or annotated status produced a block that was neither
  # projected nor reported — it just quietly stopped existing, taking any
  # dispute it was party to with it. Say it out loud instead.
  case "$status" in
    live|superseded|retired) ;;
    *) reasons="${reasons:+$reasons,}bad_status" ;;
  esac
  if [ -n "$reasons" ]; then
    printf '%s\037%s\037%s\037%s\n' "$owner" "$cf" "$key" "$reasons" >> "$INVALID_RECORDS"
  else
    printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
      "$owner" "$cf" "$key" "$claim" "$source" "$grade" "$observed" "$status" "$notes" \
      >> "$FIELD_VALID"
  fi
done < "$NORM_RECORDS"

# --- Pass 2: duplicate-live-key detection (same owner, same file) --------------
#
# Over the pass-1 SURVIVORS only. Only blocks whose EFFECTIVE status
# (default applied) is "live" ever compete for a key — a live block and its
# superseded predecessor sharing a key is the normal supersession shape, not
# a duplicate. A field-invalid sibling is already excluded from everything,
# so it cannot make its well-formed neighbour a self-contradiction.
awk -F"$US" '$8=="live"{print $1"\037"$3}' "$FIELD_VALID" | sort | uniq -c \
  | awk '$1>1{print $2}' > "$DUP_KEYS"

while IFS="$US" read -r owner cf key claim source grade observed status notes; do
  if [ "$status" = "live" ] && [ -s "$DUP_KEYS" ] \
     && grep -Fxq "${owner}${US}${key}" "$DUP_KEYS" 2>/dev/null; then
    printf '%s\037%s\037%s\037%s\n' "$owner" "$cf" "$key" "duplicate_live_key" \
      >> "$INVALID_RECORDS"
  else
    printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
      "$owner" "$cf" "$key" "$claim" "$source" "$grade" "$observed" "$status" "$notes" \
      >> "$VALID_RECORDS"
  fi
done < "$FIELD_VALID"

# --- Live projection + conflict detection --------------------------------------

awk -F"$US" '$8=="live"' "$VALID_RECORDS" > "$LIVE_RECORDS"

awk -F"$US" '{print $3"\037"$1}' "$LIVE_RECORDS" | sort -u > "$KEY_OWNER_PAIRS"
awk -F"$US" '{c[$1]++} END{for (k in c) if (c[k] >= 2) print k}' "$KEY_OWNER_PAIRS" \
  | sort > "$DISPUTED_KEYS"

# --- Absence contract, part 2 --------------------------------------------------
#
# Nothing parseable anywhere → nothing, in either mode. That is the real
# absence condition: a squad that has never written a belief block.

LIVE_COUNT=$(wc -l < "$LIVE_RECORDS" | tr -d ' ')
if [ ! -s "$NORM_RECORDS" ]; then
  exit 0
fi

# --- Mode (a): default JSON-lines dump -----------------------------------------

if [ "$MODE" = "default" ]; then
  while IFS="$US" read -r owner cf key claim source grade observed status notes; do
    jq -nc \
      --arg belief "$key" --arg owner "$owner" --arg claim "$claim" \
      --arg source "$source" --arg grade "$grade" --arg observed "$observed" \
      --arg status "$status" --arg notes "$notes" \
      '{belief:$belief, owner:$owner, claim:$claim, source:$source,
        grade:$grade, observed:$observed, status:$status, notes:$notes}' \
      2>/dev/null || true
  done < "$VALID_RECORDS"

  while IFS="$US" read -r owner cf key reasons_csv; do
    jq -nc --arg invalid "$key" --arg owner "$owner" --arg file "$cf" --arg r "$reasons_csv" \
      '{invalid:$invalid, owner:$owner, file:$file, reasons: ($r | split(","))}' \
      2>/dev/null || true
  done < "$INVALID_RECORDS"

  while IFS= read -r dkey; do
    [ -z "$dkey" ] && continue
    owners_json=$(awk -F"$US" -v k="$dkey" '$3==k{print $1}' "$LIVE_RECORDS" \
      | sort -u | jq -R . | jq -sc .)
    jq -nc --arg conflict "$dkey" --argjson owners "$owners_json" \
      '{conflict:$conflict, owners:$owners}' 2>/dev/null || true
  done < "$DISPUTED_KEYS"

  BELIEFS=$(wc -l < "$VALID_RECORDS" | tr -d ' ')
  INVALID_N=$(wc -l < "$INVALID_RECORDS" | tr -d ' ')
  CONFLICTS_N=$(wc -l < "$DISPUTED_KEYS" | tr -d ' ')
  jq -nc \
    --argjson files "$FILES" --argjson beliefs "$BELIEFS" --argjson live "$LIVE_COUNT" \
    --argjson invalid "$INVALID_N" --argjson conflicts "$CONFLICTS_N" \
    '{summary:true, files:$files, beliefs:$beliefs, live:$live, invalid:$invalid, conflicts:$conflicts}'
  exit 0
fi

# --- Mode (b): --index projection ----------------------------------------------
#
# Absence contract, the --index-only half: a prompt with nothing live to be
# told gets no section at all. The default mode above deliberately does NOT
# share this guard — see the header.

if [ "$LIVE_COUNT" -eq 0 ]; then
  exit 0
fi

# truncate_line <line> → the line, capped at 80 bytes, with "..." replacing
# whatever was cut. LC_ALL=C is set at the top of this script, so ${#s} and
# ${s:0:n} are byte operations — deterministic on every machine, unlike
# character slicing, which changes answer with the runner's locale.
#
# A byte cut can land inside a multi-byte UTF-8 sequence (a claim in any
# non-ASCII language, or this line's own em-dash), which would put a
# half-character in a prompt. So: count the trailing continuation bytes,
# read the lead byte they belong to, and keep the sequence only when it is
# complete. Never emits invalid UTF-8, at any locale.
truncate_line() {
  local s="$1" cut tmp lead last n=0 need=0
  if [ "${#s}" -le 80 ]; then
    printf '%s' "$s"
    return 0
  fi
  cut="${s:0:77}"
  tmp="$cut"
  while [ "$n" -lt 3 ] && [ -n "$tmp" ]; do
    last="${tmp: -1}"
    case "$last" in
      [$'\200'-$'\277']) n=$((n + 1)); tmp="${tmp%?}" ;;
      *) break ;;
    esac
  done
  lead="${tmp: -1}"
  case "$lead" in
    [$'\302'-$'\337']) need=1 ;;
    [$'\340'-$'\357']) need=2 ;;
    [$'\360'-$'\364']) need=3 ;;
  esac
  if [ "$need" -ne "$n" ]; then
    cut="$tmp"
    [ "$need" -gt 0 ] && cut="${cut%?}"
  fi
  printf '%s...' "$cut"
}

UNDISPUTED_RAW="$TMPDIR_WORLD/undisputed_raw.tsv"
UNDISPUTED_SORTED="$TMPDIR_WORLD/undisputed_sorted.tsv"

# The two-file NR==FNR join idiom below misbehaves on some awk
# implementations (observed: macOS's BWK/"one true" awk) when the FIRST
# file is completely empty — it silently yields nothing from the SECOND
# file too, instead of the expected "nothing to exclude". Zero disputed
# keys is the common case, so short-circuit it rather than depend on that.
if [ -s "$DISPUTED_KEYS" ]; then
  awk -F"$US" 'NR==FNR{d[$1]=1; next} !($3 in d)' "$DISPUTED_KEYS" "$LIVE_RECORDS" \
    > "$UNDISPUTED_RAW"
else
  cp "$LIVE_RECORDS" "$UNDISPUTED_RAW"
fi
# Recency-ordered: sort on Observed (column 7), descending, stable so equal
# dates keep file-then-block encounter order.
sort -t "$US" -k7,7r -s "$UNDISPUTED_RAW" > "$UNDISPUTED_SORTED"

printf '## World model\n'

TOTAL_U=$(wc -l < "$UNDISPUTED_SORTED" | tr -d ' ')
i=0
while IFS="$US" read -r owner cf key claim source grade observed status notes; do
  i=$((i + 1))
  [ "$i" -gt "$CAP" ] && break
  line="- ${key}: ${claim} — ${owner} [${grade}, observed ${observed}]"
  printf '%s\n' "$(truncate_line "$line")"
done < "$UNDISPUTED_SORTED"
REMAIN=0
[ "$TOTAL_U" -gt "$CAP" ] && REMAIN=$((TOTAL_U - CAP))
[ "$REMAIN" -gt 0 ] && printf '+%s more on disk\n' "$REMAIN"

TOTAL_D=$(wc -l < "$DISPUTED_KEYS" | tr -d ' ')
if [ "$TOTAL_D" -gt 0 ]; then
  printf '\n## Disputed\n'
  j=0
  while IFS= read -r dkey; do
    [ -z "$dkey" ] && continue
    j=$((j + 1))
    [ "$j" -gt "$DISPUTED_CAP" ] && break
    printf '\n### %s\n' "$dkey"
    while IFS="$US" read -r owner cf key claim source grade observed status notes; do
      printf -- '- [%s] %s \xc2\xb7 %s \xc2\xb7 observed %s: %s\n' \
        "$owner" "$grade" "$source" "$observed" "$claim"
    done < <(awk -F"$US" -v k="$dkey" '$3==k' "$LIVE_RECORDS" | sort -t "$US" -k1,1)
  done < "$DISPUTED_KEYS"
  REMAIN_D=0
  [ "$TOTAL_D" -gt "$DISPUTED_CAP" ] && REMAIN_D=$((TOTAL_D - DISPUTED_CAP))
  [ "$REMAIN_D" -gt 0 ] && printf '\n+%s more disputed — run squad-world\n' "$REMAIN_D"
fi

INVALID_N=$(wc -l < "$INVALID_RECORDS" | tr -d ' ')
printf '\nInvalid: %s (excluded from every projection)\n' "$INVALID_N"

exit 0

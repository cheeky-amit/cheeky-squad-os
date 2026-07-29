<!--
The shared world model — one owner's belief ledger (hard rule #13).
Path: .squad/world/claims-<owner>.md

Who writes it: the owner named IN THE FILENAME, and only that owner —
  ownership is POSITIONAL, not declared inside the file. Nothing in this
  file's body can override or claim a different owner; the filename wins,
  always. hooks/permission-request.sh enforces this structurally: a role
  is granted exactly its own .squad/world/claims-<agent_type>.md (derived
  from its own agent_type, the same way it is granted its own engagement
  record and outbox), once that role has published an engagement record
  (hard rule #11 — asserting a belief is acting). Every other
  .squad/world/ path defers to the human. Two owners are reserved and are
  NOT roles a squad ever dispatches:
    - claims-user.md      the human's own beliefs, and the rulings that
                           settle a dispute between two roles' claims.
    - claims-research.md  findings from the world, written ONLY by the
                           squad-world skill's `research` verb and only
                           through its two human gates. Absent on any
                           squad that has never run research. It uses
                           this exact schema — there is no second one —
                           under one extra restriction, below.
  The hook refuses BOTH names to any role, on purpose — a role merely
  NAMED "user" or "research" must never be able to forge either file.

THE RESEARCH GRADE CEILING — a per-owner restriction, in claims-research.md
and ONLY there. A block in that file graded `inferred` or `assumed` is
INVALID (reason: research_grade_ceiling), on top of the four required
fields below. Research may assert only `confirmed` or `reported`: a
finding is something a source said, and a synthesis of findings is not a
finding. world.sh enforces this in the parser — the grade is
on-vocabulary, it is simply too weak a grade for this one owner, so the
reason code is deliberately distinct from bad_grade. Nothing else is
affected: claims-user.md has NO ceiling (the human may assert an
inference — it is their prerogative and their name is on it), and a
role's own claims-<role>.md has none either.

Who reads it: skills/squad-world/scripts/world.sh, read-only, on behalf of
  the squad-world skill — it parses every claims-*.md, validates each
  block, detects cross-owner conflicts on identically keyed live blocks,
  and either dumps the parse as JSON lines or performs the --index
  projection (the literal text a spawn prompt pastes in verbatim). The
  human reads it directly too, as the durable record of who believes what
  and on what basis.

Lifecycle: COMMITTED — unlike the engagement record (gitignored,
  per-engagement), this file accumulates. It is never cleared on dispatch;
  that is the entire point of a shared world model — a role should not
  have to rediscover what a previous role already established. Parked and
  restored with the rest of .squad/ by squad-goal.

THE FOUR GRADES — this is the SAME vocabulary as templates/role-plan.md's
Assumptions section, not a second one invented for beliefs. One vocabulary
across the plugin, never numbers (a role cannot derive "73% confident", so
a number here would be theatre, exactly as role-plan.md argues):
  [confirmed] — checked this engagement; the Source line names the file,
                command, or URL that proves it.
  [reported]  — carried in from the goal, a hand-off, an upstream
                artifact, or the human; the Source line names which.
  [inferred]  — reasoned from something else; say what, in the claim or
                Notes.
  [assumed]   — nothing backs it directly; Source still names WHAT was
                assumed FROM (a plausible default, a convention, a guess)
                — "assumed" is a grade of evidence, not an excuse to leave
                Source blank. A blank Source is invalid regardless of
                grade (see below).

HARD RULE #13 — "a belief with no source is a rumor." Claim, Source,
Grade, and Observed are ALL REQUIRED on every block. world.sh is the
mechanical guarantee: a block missing any of the four, or carrying a Grade
outside the vocabulary above, is INVALID and is excluded from every
projection — never reaches a prompt, never counts as "live" for anything.
This is enforced by a parser, not by asking a role nicely.

DISPUTED IS DERIVED, NEVER WRITTEN BY HAND. There is no "Status: disputed"
value and none may be added. Two `live` blocks under the SAME key from
DIFFERENT owners are what a dispute IS — world.sh detects this by
comparison, on every run; nothing about the block itself ever says the
word. A conflict is adjudicated by the human alone (hard rule #10's
spirit — verification decides, never averages) — usually by that human
writing their own ruling as a `live` block in claims-user.md under the
same key, which does not erase the other two; it just makes the human's
answer visible alongside them, same as everyone else's.

WHAT THIS DOES NOT DO — stated plainly, not left to be discovered:
  - No TTL / no staleness decay. A belief does not expire on a timer;
    if it is wrong now, mark it `superseded` (see Status below) — don't
    wait for it to rot out.
  - No semantic contradiction detection. Only IDENTICALLY KEYED live
    blocks are ever compared. Two owners can contradict each other in
    completely different words, under different keys, and nothing here
    will ever notice. Pick keys that make real overlaps collide.
  - No auto-resolution. Not latest-wins, not "the higher grade wins",
    never. A conflict line just names every claimant; a human decides.
  - No cross-squad merge. A parked squad's world/ is its own; nothing
    folds one squad's beliefs into another's.
  - Grades are self-reported. Nothing here can verify that a Source: line
    tells the truth — the parser checks the field is PRESENT and
    on-vocabulary, never that it is honest. That is a limit of the whole
    system, not a bug in this file.
-->

## Belief: <kebab-case-key>

<!--
  The key is how a claim is compared across owners — pick one that would
  collide with a genuinely competing claim under a different owner's
  file, and would NOT collide with something unrelated. "checkout-latency"
  is a key; "the thing about checkout" is not.
-->

Claim: <one sentence, falsifiable — someone reading only this line and the
  Source below should be able to go check it themselves>
Source: <file path, command, URL, tool read, or a named person>   REQUIRED
Grade: confirmed | reported | inferred | assumed                  REQUIRED
Observed: <ISO-8601 date, e.g. 2026-07-29>                         REQUIRED
Status: live
Notes: <optional — caveats, scope, anything a reader should know before
  trusting this at face value>

<!--
  Status is optional and defaults to `live`. The only three values are
  live | superseded | retired — anything else is INVALID, reported as
  such, and excluded from every projection, exactly like a missing field.
  Kept on its own line rather than annotated inline: the parser strips a
  trailing HTML comment from a field value, but a template that models a
  spelling only a strip saves is a template teaching a bad habit.
-->

<!--
  Notes is the only optional field. Everything above it is required —
  see HARD RULE #13 at the top of this file.
-->

---

## Worked example

## Belief: checkout-p95-latency-exceeds-3s

Claim: Checkout page p95 load time on mobile exceeds 3 seconds.
Source: `reports/lighthouse-2026-07-28.json`, field `metrics.p95_ms`
Grade: confirmed
Observed: 2026-07-28
Status: live
Notes: Measured against the `mobile-throttled` Lighthouse profile only;
  desktop was not checked this engagement.

<!--
  A second owner disagreeing under the SAME key —
  `.squad/world/claims-scout.md`, say —

  ## Belief: checkout-p95-latency-exceeds-3s

  Claim: Checkout p95 is under 1s; the audit measured a stale build.
  Source: `reports/scout-recheck-2026-07-29.json`
  Grade: reported
  Observed: 2026-07-29
  Status: live

  — is not an error. It is exactly what world.sh's `conflict` line and
  --index's "## Disputed" section exist to surface: two owners, same key,
  live, disagreeing. Neither block is invalid. Nobody averages them.
  The human looks at both and rules — most often by adding their own
  `live` block under the same key in .squad/world/claims-user.md.
-->

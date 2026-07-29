---
verdict: <met | partial | unmet>
verified_at: <ISO-8601 datetime>
goal_mode: <one-time | multi-use | evergreen>
signals_pass: <count>
signals_fail: <count>
signals_human: <count>
escalations_open: <count>
resolved_escalations:
  - <role>
  - <role>
---

# Squad verification

<!--
  Written by /cheeky-squad-os:squad-verify — the squad's supervisor.
  Synthesis summarizes; verification decides. This file is the only
  authority for declaring the squad goal met.

  Re-running verification OVERWRITES this file — it always reflects the
  latest check against .squad/goal.md's Definition of done.

  Statuses:
    PASS            — observably true, with a machine evidence pointer
    FAIL            — observably false, or the named artifact is missing
    NEEDS-HUMAN     — not mechanically checkable; a human must confirm
    PASS (attested) — a NEEDS-HUMAN row, or the signal an escalation was
                       blocking, converted to PASS by a recorded human
                       attestation (hard rule #15). PERMANENT and distinct
                       from a plain PASS forever — see the evidence-
                       attribution split below. Never rewritten to plain
                       PASS on a later run; the attestation stays quoted.

  Verdict:
    met     — every signal PASS or PASS (attested), AND escalations_open == 0
    partial — at least one PASS or PASS (attested), AND at least one FAIL,
              NEEDS-HUMAN, or open escalation
    unmet   — no signal PASS or PASS (attested)

  THE EVIDENCE-ATTRIBUTION SPLIT (hard rule #15) — the human meets the same
  evidence bar the machine does. Wherever a signal or escalation is settled
  by a human rather than by a mechanical check, the Evidence line names WHO
  checked WHAT and WHEN, quoted verbatim — never paraphrased into "confirmed
  by human":

    **Evidence (machine):** <file path read, or command + quoted output>
    **Evidence (human attestation, <ISO-8601 date>):** "<the human's
      what-I-checked / what-I-found, verbatim>"

  A bare "it's fine" earns exactly one push-back asking what was checked;
  if the human still declines to elaborate, record that verbatim too —
  the human is never blocked, they are put on the record. The two evidence
  forms are never merged into one line and a human attestation is never
  silently upgraded to look machine-verified.

  CRITICAL ABSENCE RULE (hard rule #11) — read before rendering ## Process:
    No frontmatter field accompanies ## Process; none is added by this
    feature. The section itself is conditional: render it ONLY when at least
    one role in this engagement published an engagement record at
    .squad/role-plan-<role>.md (see templates/role-plan.md). If NO role
    published one, OMIT ## Process ENTIRELY — not as an empty heading, not as
    a table of dashes. A squad that never used the feature must produce the
    same SECTIONS a pre-#11 run produced — the engagement record adds nothing
    to a verification that had no record to read.

  CRITICAL ABSENCE RULE (hard rule #14) — read before setting escalations_open
  or resolved_escalations, or rendering ## Escalations:
    Both frontmatter fields are computed from the same input — the set of
    published engagement records — and are OMITTED TOGETHER, ENTIRELY, when
    no role in this engagement published a record at .squad/role-plan-<role>.md.
    Omitted means absent from the frontmatter block, not present as `0`,
    not present as `[]`, not present as `null`. Same discipline as ## Process
    above: a squad that never used the engagement-record feature produces a
    verification.md with the same KEYS a pre-#14 run produced. When at least
    one record exists, compute mechanically —
      escalations_open = |records with status: escalated|
                          − |their roles named in resolved_escalations|
    — from two inputs neither of which a role controls (see THE RESOLUTION
    RULE in templates/role-plan.md). Once records exist the two fields are
    present even when nothing has been ruled on yet: escalations_open takes
    its real count and resolved_escalations is written as the empty flow list
    `[]`. Present-and-empty and omitted-entirely are different states and are
    never collapsed — the first says "nobody has ruled yet", the second says
    "this squad never used the feature". Otherwise the list is block style,
    one role name per dashed line, indented two spaces. ## Escalations itself
    follows ## Process's rule: render it only when at least one record has
    status: escalated; otherwise omit the heading entirely.
-->

## Signal: <signal text, verbatim from the goal's Definition of done>

- **Status:** <PASS | FAIL | NEEDS-HUMAN | PASS (attested)>
- **Evidence (machine):** <file path read, or command + quoted output — use this line for PASS/FAIL/NEEDS-HUMAN>
- **Evidence (human attestation, <date>):** <only for PASS (attested) — the verbatim what-checked/what-found, in quotes>
- **Notes:** <optional — anything that qualifies the evidence>

<!-- one "## Signal:" section per Definition-of-done bullet -->

## Role deliverables

| Role | Scope | Files found | Role goal present |
| --- | --- | --- | --- |
| <name> | <file_scope globs> | <N> | <yes/no> |

<!-- flag any role with 0 files found — its workstream produced nothing -->

## Process

<!-- OMIT THIS ENTIRE SECTION if no role in this engagement published a
     record at .squad/role-plan-<role>.md — see the CRITICAL ABSENCE RULE
     above. Render it only when at least one record exists; roles with no
     record still get a row (Record: no) so the table stays honest about who
     acted without declaring intent — that is process evidence too, not a
     reason to hide the row. Judge the process, not only the artifact
     (LOGIC.md §5.2). -->

| Role | Record | Status | Confirmed | Reported | Inferred | Assumed | Deliverables declared → delivered |
| --- | --- | --- | --- | --- | --- | --- | --- |
| <name> | <yes/no> | <active/amended/—> | <N> | <N> | <N> | <N> | <N> → <N> |

<!-- One row per active role, in roster order. For "Record: no" rows, leave
     Status/grade/deliverable columns as "—". For a malformed record (present
     but unparseable — no frontmatter, missing sections), report
     "Record: yes" with zero grade counts and say why in a Notes line under
     the table — never error, never drop the row.
     "Deliverables declared → delivered" is the count from the record's
     ## Deliverables list vs. how many of those exact paths exist on disk;
     list any missing paths, backtick-quoted, directly under the table row
     they belong to. Undeclared artifacts (files produced but never named in
     ## Deliverables) are noted the same way, labeled "undeclared work" —
     surfaced, not judged. -->

### Assumptions surfaced to the human

<!-- Every `[assumed]` bullet from every published record, quoted verbatim
     (including its "if wrong → …" clause), grouped by role. This is the raw
     material for squad-verify's forcing rule: a Definition-of-done signal
     named in one of these clauses cannot PASS on that role's own output
     alone — at most NEEDS-HUMAN, with the assumption quoted. Omit a role's
     block if its record has no [assumed]-grade bullets; omit this whole
     subsection if no published record has any (keep ## Process itself if at
     least one record exists — the table above still carries the grade
     counts). -->

**<role-name>**
- [assumed] <bullet, quoted verbatim>

## Escalations

<!-- OMIT THIS ENTIRE SECTION if no published engagement record has
     status: escalated — see the hard-rule-#14 CRITICAL ABSENCE RULE above.
     Render it only when at least one exists; one block per escalated
     record, most-recently-fired first. This section, together with
     resolved_escalations in the frontmatter, is the ONLY place the human's
     ruling on an escalation is recorded anywhere in the plugin (THE
     RESOLUTION RULE, templates/role-plan.md) — a role cannot write here,
     structurally (the .squad/ reservation), so nothing below can have been
     forged by the role it is about. -->

### <role-name>

- **Fired:** "<the fired stop-condition bullet, verbatim from the record's `fired:` field>"
- **Blocks:** <the Definition-of-done signal(s) this escalation blocks a `met` verdict on — quote the signal text, or "no signal directly; blocks `met` on escalations_open alone">
- **Ruling:** <UNRESOLVED, or the human's ruling quoted verbatim with attribution and date — same evidence-attribution split as above: `**Evidence (human attestation, <date>):** "<verbatim>"`>

<!-- Once a ruling is recorded here AND the role name is added to
     resolved_escalations in the frontmatter, escalations_open drops by one
     on the next verify run. Adding the name to resolved_escalations without
     writing the ruling here (or vice versa) is a malformed resolution —
     flag it, don't silently count it as closed. -->

## Verdict

<one plain-language paragraph: the verdict, why, and the single suggested
next step — declare done / re-dispatch named roles via squad-spawn /
resolve the NEEDS-HUMAN items and re-verify / rule on the open escalation(s)
in ## Escalations above and re-verify>

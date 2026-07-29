---
verdict: <met | partial | unmet>
verified_at: <ISO-8601 datetime>
goal_mode: <one-time | multi-use | evergreen>
signals_pass: <count>
signals_fail: <count>
signals_human: <count>
---

# Squad verification

<!--
  Written by /cheeky-squad-os:squad-verify — the squad's supervisor.
  Synthesis summarizes; verification decides. This file is the only
  authority for declaring the squad goal met.

  Re-running verification OVERWRITES this file — it always reflects the
  latest check against .squad/goal.md's Definition of done.

  Statuses:
    PASS        — observably true, with an evidence pointer
    FAIL        — observably false, or the named artifact is missing
    NEEDS-HUMAN — not mechanically checkable; a human must confirm

  Verdict:
    met     — every signal PASS
    partial — at least one PASS, at least one FAIL or NEEDS-HUMAN
    unmet   — no signal PASS

  CRITICAL ABSENCE RULE (hard rule #11) — read before rendering ## Process:
    No frontmatter field accompanies ## Process; none is added by this
    feature. The section itself is conditional: render it ONLY when at least
    one role in this engagement published an engagement record at
    .squad/role-plan-<role>.md (see templates/role-plan.md). If NO role
    published one, OMIT ## Process ENTIRELY — not as an empty heading, not as
    a table of dashes. A squad that never used the feature must produce the
    same SECTIONS a pre-#11 run produced — the engagement record adds nothing
    to a verification that had no record to read.
-->

## Signal: <signal text, verbatim from the goal's Definition of done>

- **Status:** <PASS | FAIL | NEEDS-HUMAN>
- **Evidence:** <file path read, or command + quoted output; for NEEDS-HUMAN, what a human must check and how>
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

## Verdict

<one plain-language paragraph: the verdict, why, and the single suggested
next step — declare done / re-dispatch named roles via squad-spawn /
resolve the NEEDS-HUMAN items and re-verify>

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

## Verdict

<one plain-language paragraph: the verdict, why, and the single suggested
next step — declare done / re-dispatch named roles via squad-spawn /
resolve the NEEDS-HUMAN items and re-verify>

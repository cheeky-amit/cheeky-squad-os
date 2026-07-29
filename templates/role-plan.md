---
# The engagement record — a role's declared intent, written BEFORE it acts.
# Path: .squad/role-plan-<role>.md   (hard rule #11)
#
# Who writes it: the role itself, as Step 0 of every invocation, before its
#   first write to anything else. The PermissionRequest hook grants this path
#   unconditionally (it is the bootstrap) and gates every other auto-approval
#   on its existence. The grant is derived from the role's own agent_type, so
#   one role can never publish another's record.
# Who reads it: the human, auditing what a role decided and on what basis;
#   squad-spawn's synthesis (declared-vs-produced); squad-verify (process
#   evidence, §5.2 — judge the process, not only the artifact).
#   Downstream ROLES do not read it — hand-offs ride .squad/role-comm-*.
#   Do not duplicate that channel here.
# Lifecycle: per-engagement, gitignored. The dispatcher clears the records of
#   the roles it is about to dispatch, and only those — a parallel add-a-role
#   run never deletes a running role's record. squad-verify quotes whatever
#   must outlive it into .squad/verification.md.
#
# THE UNCERTAINTY RULE — grade by evidence class, never by number.
# A role cannot derive "73% confident", so a number here is theatre. Every
# assumption carries exactly one grade, and each grade owes something:
#   [confirmed] — checked this engagement; MUST name the file, command, or URL
#                 that proves it.
#   [reported]  — carried in from the goal, a hand-off, an upstream artifact,
#                 or the human; MUST name the source.
#   [inferred]  — reasoned from something else; MUST say how.
#   [assumed]   — nothing backs it; MUST name what breaks if it is wrong, as
#                 "if wrong → <deliverable or Definition-of-done signal>".
# That last clause is load-bearing: squad-verify refuses to PASS a Definition-
# of-done signal on the strength of the same role's [assumed] bullet. Naming
# the blast radius is what makes the guess reviewable instead of invisible.
role: {{role}}          # must equal the filename's <role>; on mismatch the filename wins
created: {{created}}    # ISO-8601
status: {{status}}      # active | amended
---

# Engagement record — {{role}}

## Task read

<!-- One paragraph: what this role understands its task to be THIS invocation.
     Write it from the role goal in your own words rather than restating it —
     the point is to expose a misread before any file changes. If your reading
     diverges from the role goal, that divergence is the headline, not a
     footnote. -->

## Intended approach

<!-- 3–7 ordered steps. Each names an action and the artifact it touches:
     "read X, compute Y, write Z". A reader must be able to falsify a step —
     "analyse the data" is not a step, "read data/*.json and build the
     per-flow table" is. -->

## Deliverables

<!-- The exact paths this invocation will produce, one backtick-quoted path
     per bullet. These should match the role goal's owned outputs; any
     difference is declared here, not discovered afterwards. squad-spawn's
     synthesis diffs this list against what actually appeared on disk. -->

## Assumptions

<!-- One bullet per assumption, graded per the frontmatter rule:
       - [confirmed] <claim> — evidence: <file, command, or URL>
       - [reported]  <claim> — source: <goal / hand-off / artifact / human>
       - [inferred]  <claim> — reasoning: <how you got there>
       - [assumed]   <claim> — if wrong → <deliverable or DoD signal>
     An empty section asserts "no assumptions". Only leave it empty if that
     is true; an unstated assumption is the one that costs the most. -->

## Amendments

<!-- Only when status: amended. Append-only, timestamped: what changed and
     why. Never rewrite the sections above — the value of this record is that
     it says what you thought BEFORE you knew better. -->

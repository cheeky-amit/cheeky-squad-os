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
# THE RESOLUTION RULE — hard rule #14; read before adding any field here.
# There is NO `resolved` status and NO `resolution:` field, anywhere in this
# schema, and none may be added. The status enum stops at `escalated` on
# purpose: a role that could write its own resolution could unblock a `met`
# verdict with one in-scope write, which defeats hard rule #10 (verification
# decides) exactly as the pre-v0.4.1 `.squad/` forgery hole did. The human's
# ruling on an escalation lives in exactly one place — `.squad/verification.md`
# (squad-verify-owned, structurally unwritable by any role) — never here.
# Residual, stated honestly: a role can flip its own `escalated` back to
# `active`. That is behaviorally identical to never having stopped at all,
# which is already the acknowledged aspirational half of #14. What a role
# cannot do, under any status value, is mint the human's ruling.
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
status: {{status}}      # active | amended | escalated — no other value; see
                         #   THE RESOLUTION RULE above for why there is no
                         #   "resolved"
fired: {{fired}}        # "" unless status: escalated. When escalated, this
                         #   is the fired stop-condition bullet from this
                         #   role's role-goal.md ## Stop conditions, copied
                         #   VERBATIM — not paraphrased, not summarized. This
                         #   is what squad-verify quotes into
                         #   .squad/verification.md's ## Escalations.
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

<!-- Everything below this line is written ONLY when status: escalated (hard
     rule #14). A role that never fires a stop condition leaves these three
     headings out of the file entirely — do not render them empty. Once
     written, this record's job is done: the role stops. It does not poll for
     a ruling, does not retry, does not add a fourth section. The human's
     response, when it comes, is recorded in .squad/verification.md, not
     here — see THE RESOLUTION RULE above. -->

## What happened

<!-- One paragraph. Name the exact stop-condition bullet that fired (it must
     match `fired:` in the frontmatter verbatim), the evidence that it fired
     — what you observed, not what you suspected — and which numbered step of
     ## Intended approach you were on. "It seemed stuck" is not evidence;
     "step 3, `POST /flows/{id}/actions`, returned 403 on the second attempt"
     is. -->

## State of the work

<!-- One line per path listed in ## Deliverables, in the same order:
       - `<path>` — complete
       - `<path>` — partial: <the gap, named plainly — what's missing, not
         just that something is>
       - `<path>` — untouched
     A deliverable this run never got to is "untouched," not silently
     dropped from the list. squad-verify's process table reads this section
     to judge declared-vs-delivered against an interrupted run, not a
     finished one. -->

## What would unblock

<!-- The smallest thing that resumes this work — a specific grant, a specific
     file, or a specific ruling, not "someone should look at this." Say what
     the human (or another role) would need to hand over or decide. This is
     the input to squad-verify's attestation: whatever the human records in
     .squad/verification.md's ## Escalations should be answerable by reading
     this bullet, not by re-deriving the whole engagement from scratch. -->

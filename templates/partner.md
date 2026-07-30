<!--
The partner model — the human's own standing brief (hard rule #12).
Path: .squad/partner.md

Who writes it: the squad-partner skill, and only that skill. Every
  sentence in this file must have been confirmed by the human IN THE SAME
  TURN it was written — not inferred from behavior, not carried over from
  a hunch, not accumulated silently across sessions. "Told, not inferred"
  is the entire feature: a partner model assembled by inference is a
  dossier; this one is a brief the human dictates.

  hooks/permission-request.sh already reserves this path structurally —
  .squad/partner.md is on the same reserved-artifact list as goal.md and
  roster.json, so every role's write to it defers to the human, including
  a write attempted by a role literally named "partner". No change to
  that hook was needed for this file to exist safely.

Who it describes: the single commanding human running this project — not
  the initiative, not a role, not a third party. This file never names or
  characterizes anyone but that one human. No secrets, no notes about
  other people. That is a CHECK squad-partner runs over the body before
  every create and every update — a line that characterizes someone else
  or carries a credential is named, rewritten to keep the instruction
  without the person or the secret, re-confirmed, and only then written.
  Not a claim this comment makes on the file's behalf: privacy here is a
  default offer (below), so a sentence about someone who never consented
  is one declined ignore-line offer away from living in version control.

Who reads it: squad-spawn bakes the full body into every spawn prompt at
  dispatch time (hard rule #4) — the file is typically gitignored and so
  absent inside an isolated worktree; baking is the only reliable
  channel. session-start.sh appends it to a live session's context after
  the goal (the goal always comes first). squad-onboard reads it silently
  once, to pre-populate the goal's Out of scope from Standing constraints
  and to offer a one-line staleness note on a file older than 30 days —
  never as a nag.

Lifecycle: survives every squad park/switch untouched — squad-goal parks
  and restores SQUAD-scoped state (goal.md, roster, world/, ...); this
  file describes the human, not the squad, so it is never part of that
  move. It persists across as many squads and goals as this project ever
  runs.

Privacy: NOT enforced by any mechanism in this file or this plugin. The
  create flow offers, once, to add ".squad/partner.md" to the project's
  .gitignore in the SAME write as the file itself — accepting keeps it
  out of version control by default; declining is an explicit, informed
  choice to commit a model of a person. Say this as "the plugin never
  commits it for you, and proposes the ignore line at creation" — never
  as "it is private". This is a model of a person in a git repo, and the
  source paper (Collins et al. §5.3) flags such models as dual-use.

Exactly three sections. Two were deliberately cut and must not return:
  - Expertise — self-graded, never checked against a consequence; theatre.
  - A standalone Attention budget — over-structures a file that should
    stay well under a hundred lines. Its two load-bearing lines (batch
    questions; a deadline tie-break) live inside Decide vs. ask instead.

No CI lint enforces this file's shape — nothing machine-parses it, unlike
  roster.json, which the roster lint guards because a hook reads it.
-->

---
created: <ISO-8601 datetime>
updated: <ISO-8601 datetime>
---
# Partner model

## Decide vs. ask

<!--
  Two lists. Nothing goes in either one unless the human said it, this
  turn. "Decide without me:" is what a role should just settle and note,
  not raise. "Always ask first:" is what must come back to the human
  before a role acts, no matter how confident the role is.

  This section may also carry ATTENTION LINES — short standing
  instructions about how ask-first items should reach the human, e.g.
  "batch questions, one block per session" so a role doesn't ping five
  times in a row. If the human gives a DEADLINE TIE-BREAK — what happens
  when an ask-first item collides with a deadline and there's no time to
  wait for an answer — record it here too, verbatim enough to act on.

  Decide without me:
  - <thing the human said a role may just settle>
  - <another>

  Always ask first:
  - <thing the human said must always come back to them>
  - <another>

  Attention:
  - <e.g. "batch questions, one block per session, not one at a time">
  - <deadline tie-break, if the human gave one, e.g. "if an ask-first
    item is still open 4 hours before a hard deadline, proceed on the
    safer of the available options and flag it clearly in the hand-off">
-->

## Standing constraints

<!--
  Invariants that bind EVERY squad in this project, the same way
  .squad/goal.md's outcome and Definition of done bind one squad. These
  are not goal-specific exclusions — squad-onboard pre-populates a new
  goal's Out of scope from this list, not the other way around.

  - <constraint the human stated, that applies no matter what the squad
    is currently working on>
  - <another>
-->

## Beliefs to check

<!--
  Hypotheses the human holds, framed so a role that touches one can
  actually test it — not inherited as settled fact. A role that touches
  a belief in this list reports back one of exactly three outcomes:
  confirmed / contradicted / could not test. This is the direct answer
  to the paper's "possibly false beliefs" — it turns the human's own
  assumptions into work, instead of quietly trusting them.

  This is NOT the same file as .squad/world/claims-user.md. That ledger
  holds beliefs about the WORLD/DOMAIN, confirmed or disputed by
  evidence graded confirmed/reported/inferred/assumed. This section holds
  beliefs the human holds ABOUT THEIR OWN SITUATION that a role should
  actively verify while doing its work — the two are related in spirit,
  not the same mechanism, and this section has no grade vocabulary of
  its own; "confirmed / contradicted / could not test" is a report on
  an ACTION taken, not an evidence grade.

  - <belief the human holds, stated so it's checkable — e.g. "our top
    channel by revenue is still email, not paid search">
  - <another>
-->

---

## Worked example

---
created: 2026-07-29T14:02:00Z
updated: 2026-07-29T14:02:00Z
---
# Partner model

## Decide vs. ask

Decide without me:
- Copy tone and wording for internal-only artifacts (hand-offs, plans, notes).
- Which file format to use for a deliverable, unless I've named one.
- Minor sequencing of independent workstreams.

Always ask first:
- Anything that touches a live customer-facing page or email before it ships.
- Any spend over $200, even if it's within a role's stated budget.
- Renaming or deleting anything already shared with the rest of the team.

Attention:
- Batch questions — one block per session, not one message at a time.
- Deadline tie-break: if an ask-first item is still open 4 hours before a
  hard deadline, proceed on the more conservative option and flag it
  clearly at the top of the hand-off — don't ship silently and don't miss
  the deadline waiting on me.

## Standing constraints

- Never mention a competitor by name in anything customer-facing.
- All customer data stays out of prompts sent to a third-party API —
  redact or aggregate first.
- English only for any customer-facing copy, even in drafts.

## Beliefs to check

- Our highest-converting channel is still email, not paid search — this
  was true 6 months ago and I haven't rechecked it.
- The Klaviyo flow "Welcome Series v2" is the one actually live, not
  "Welcome Series v1" — I think v1 was archived but I'm not certain.

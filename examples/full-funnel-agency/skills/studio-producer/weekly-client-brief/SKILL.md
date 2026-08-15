---
name: weekly-client-brief
description: Use when the Monday client brief is due, or when someone asks "where does the program stand" — turns a week of channel activity into one page of decisions, owners, and next moves rather than a metrics dump.
---

# weekly-client-brief

Source: https://github.com/msitarzewski/agency-agents/blob/main/project-management/project-management-studio-producer.md

Adapted from that agent's Strategic Portfolio Review template. The original reports a
quarter of portfolio performance to an executive audience. This is the same instinct at
a different altitude: one week, one client, one page — and every section is a decision
rather than a status. Sections that only restated numbers were cut, because the numbers
already live in `deliverables/measurement/` and repeating them is how a brief becomes a
thing nobody reads.

## The rule this skill exists to enforce

**A brief with no decision in it is a status email.** If a week genuinely produced no
decision, that is the headline — say so and name what is blocking one. Never pad the
page with movement that changed nothing.

## Before writing

1. Read the reconciled numbers from `deliverables/measurement/weekly-reconciliation.md`.
   Never quote a channel-reported figure directly in a client brief; if reconciliation
   has not landed, the brief ships with the number marked *unreconciled* and says so.
2. Read the open rows in `deliverables/program/risk-register.md`. Any row whose trigger
   fired this week is a brief item whether or not anyone acted on it.
3. Read the hand-off manifests published since the last brief. Each one is either a
   decision that was made or a decision that is now waiting on someone.

## The page

Keep it to one screen. Six headings, in this order, and drop any that has nothing real.

```markdown
# <Client> — week of <YYYY-MM-DD>

## Where we are against the goal
<One sentence naming the goal's headline metric, this week's value, and the
direction. No table.>

## Decisions made this week
- <decision> — decided by <name>, on <the evidence>, effective <date>

## Decisions waiting on you
- <the decision, stated as a question with two named options> — needed by <date>,
  because <what stalls without it>

## What changed in the work
- <channel or workstream>: <what shipped or stopped>, <the observed effect or
  "too early to read">

## Risks that moved
- <risk> — <what changed>, <owner>, <the response we pre-agreed>

## Next week
- <the two or three things that will actually happen, each with an owner>
```

## Writing rules

- **Name the human, not the seat.** "Decided by the client's head of growth" is a
  sentence nobody can follow up on.
- **Every waiting decision carries a cost of delay.** "Needed by Thursday because the
  next creative flight is briefed Friday" is a deadline; "as soon as possible" is not.
- **"Too early to read" is a legitimate result** and is preferred over a directional
  claim on four days of data. Say which date it becomes readable.
- **No forecast without a stated method.** If a projection appears, one clause says how
  it was produced ("holding last 14 days' cost per acquisition flat").
- **No language implying a price change, promotional offer, or discount** — this
  program's brand constraint forbids it, and a brief that proposes one wastes a cycle.

## Scope boundary

This skill writes the client-facing page only. Program risk lives in
[`program-risk-register`](../program-risk-register/SKILL.md) and is *cited* here, never
re-derived. Channel mechanics — why a bid strategy changed, what a discrepancy turned
out to be — belong to the roles that own them; this brief links to their artifacts and
states the decision that came out of them.

## Done when

- Every section either has content or is absent — no empty headings.
- Every decision line names a human and a date.
- Every number traces to a reconciled source, or is explicitly marked unreconciled.
- The page fits on one screen.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match), msitarzewski/agency-agents (project-management-studio-producer.md — this skill, adapted from its Strategic Portfolio Review template), obra/superpowers (no match — engineering workflow), web search for agency reporting templates (nothing with a licence clean enough to attribute). Execution dimension: not applicable — this role operates no platform, so no execution search was run.
Intake date: 2026-08-15
Known limits: Assumes the reconciliation artifact it quotes already exists; says nothing about producing one. Written for a weekly cadence — a monthly or quarterly client would need different section weighting, not this file with the dates changed. Contains no guidance on presenting to a room, only on writing the page.
Assumed superseded: this skill reflects what research found at intake, not the best way that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than treating this as final.

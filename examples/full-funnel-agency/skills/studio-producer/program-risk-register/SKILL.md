---
name: program-risk-register
description: Use when a program-level risk needs logging, reviewing, or closing — anything that could cost the program its deadline, its budget, or its measurability, as distinct from a channel underperforming.
---

# program-risk-register

Source: https://github.com/msitarzewski/agency-agents/blob/main/project-management/project-management-studio-producer.md

Adapted from that agent's "Risk Management and Contingency" section. The original lists
risk categories and asks for mitigation strategies in prose. Prose risk sections age
badly — nobody can tell six weeks later whether a risk fired. This version makes every
row mechanically checkable: a trigger you could observe, a response agreed *before* the
trigger fires, and an owner who is a person.

## What belongs here, and what does not

**In:** anything that threatens the program's deadline, its budget envelope, its
measurability, or a dependency the squad does not control — a client-side approval that
keeps slipping, a platform policy change, a data source that may disappear, a spend
commitment made before the tracking that would justify it.

**Out:** a channel performing below target. That is performance, not risk, and it
belongs in the media buyer's pacing review. The test: if the fix is "optimize it", it
is not a risk register row.

## The register

One file, `deliverables/program/risk-register.md`, append-only within a program. Rows
are closed, never deleted — a closed row is the evidence that the response worked.

```markdown
## R<n> — <one-line risk, stated as a thing that could happen>

- **Trigger:** <the observable condition that means this is now happening —
  a number crossing a line, a date passing, a file not existing>
- **Impact if it fires:** <which goal signal or deadline it costs, named>
- **Owner:** <a person, not a role>
- **Pre-agreed response:** <what we do the day it fires, decided now, while
  nobody is under pressure>
- **Status:** open | fired <date> | closed <date> — <one line on how>
```

## Rules

1. **A trigger you cannot observe is not a trigger.** "If the client goes quiet" is a
   mood. "If the creative approval for flight 3 is not returned by 2026-09-04" is a
   trigger.
2. **The response is agreed before the fire, not after.** The whole value of the
   register is that the hard call was made calmly. If a row has no response, it is not
   finished being written.
3. **One owner.** Two owners is zero owners.
4. **Review every open row weekly**, in the same pass that produces the client brief.
   A row nobody has looked at in three weeks is either closed or was never real.
5. **A fired row appears in the next client brief**, whether or not the response
   worked. Suppressing a fired risk is how the client finds out from someone else.

## Seeding a new program

Open at least these four rows on day one, then add what the specific engagement
demands:

- Measurement is not trustworthy yet, but spend is already committed.
- A client-side approval sits on the critical path for creative or lifecycle.
- One channel carries more than half the program's spend (concentration risk).
- A platform or policy change lands mid-program and invalidates a targeting or
  measurement assumption.

## Scope boundary

This register does not track task status — the squad's task list does. It does not
track channel performance — [`budget-pacing-review`](../../performance-media-buyer/budget-pacing-review/SKILL.md)
does. It tracks only the things that would change the program's shape if they happened.

## Done when

- Every open row has a trigger, an impact, one owner, and a pre-agreed response.
- Every row that fired this week appears in this week's client brief.
- No row has been untouched for more than 14 days.

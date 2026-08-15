---
name: budget-pacing-review
description: Use for the weekly cross-channel spend decision, or any time someone proposes moving budget between search, shopping, and paid social — produces one table and one written reallocation decision with a rule for when spend does not move.
---

# budget-pacing-review

Source: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-ppc-strategist.md
Also drawn from: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-paid-social-strategist.md

Adapted from the PPC strategist's budget allocation and pacing frameworks, with the
paid-social agent's cross-platform split logic folded in. The two sources each solve
half of a problem this squad holds in one seat: search reasons about pacing and
diminishing returns, social reasons about frequency and platform split. Held apart, the
two halves produce two budget recommendations that cannot both be acted on. Held
together, there is one budget and one decision.

The other deliberate change: the sources describe *how to think about* allocation. This
describes **when spend moves and when it explicitly does not**, because the expensive
failure mode in a weekly cadence is not a bad reallocation — it is reallocating every
week on noise.

## The one table

Rebuild it weekly, over a trailing 28-day window (`PACING_WINDOW_DAYS`), from
reconciled numbers only. One row per channel-and-funnel-stage, never per campaign.

| Row | Spend (28d) | Results | Cost per result | vs target | Δ vs prior 28d | Constraint |
|---|---|---|---|---|---|---|

**Constraint** is the column that makes this table useful, and it takes exactly one of
four values:

- `budget` — hitting the daily cap while at or under target. Headroom exists.
- `auction` — impression share or reach lost to rank, not budget. More money buys less.
- `creative` — frequency climbing and click-through declining. More money buys fatigue.
- `none` — spending freely, under target, no ceiling in sight.

## The reallocation rule

Move budget **only** when all three hold:

1. The receiving row's constraint is `budget` — it can absorb money.
2. Its cost per result has been at or under target for **two consecutive** 28-day
   windows. One window is noise.
3. The giving row's constraint is `auction` or `creative`, or it has been over target
   for two consecutive windows.

If all three hold, move no more than **20% of the giving row's budget in one week**.
Larger moves reset learning on both sides and cost two weeks to find out.

If they do not all hold, **write down that spend does not move, and why.** That line is
the deliverable. A pacing review whose only possible output is a change will invent one.

## Constraint-specific responses

- `auction` — do not add budget. Route to the creative-strategist for a differentiated
  angle, or accept the ceiling and say so in the brief.
- `creative` — do not add budget. Raise a refresh request; note the frequency figure and
  the date the decline started.
- `budget` and over target — the problem is efficiency, not money. Audit before funding.
- `none` — this row is not yet at its ceiling. Find the ceiling before reallocating away
  from it.

## Seasonality and commitments

- Note any date-bound demand shift already known (a category's seasonal peak, a product
  launch) as a **planned** deviation, decided in advance and logged in the risk register
  if it commits spend ahead of measurement.
- Never justify a spend increase with an expected promotional event — this program does
  not run promotional or discount-led messaging, so no plan may assume one.

## Output

Append to `deliverables/media/pacing-<YYYY-MM-DD>.md`: the table, the constraint per
row, the decision (including "no change"), the amount moved, and the two-window evidence
that justified it. The studio-producer's brief quotes the decision line verbatim.

## Scope boundary

Structural problems found while pacing — a campaign that should not exist, a bid
strategy set against a stale conversion definition — go to
[`paid-media-audit`](../paid-media-audit/SKILL.md), not into this file. This skill
decides where money goes; that one decides whether the container deserves money.

## Done when

- Every row has a constraint value.
- The decision is written, including a "no change" decision with its reason.
- No single move exceeds 20% of the giving row's budget.
- Every number came from the reconciled source, not from a platform's own report.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match), msitarzewski/agency-agents (paid-media-ppc-strategist.md — primary source; paid-media-paid-social-strategist.md — cross-platform split logic folded in), obra/superpowers (no match), web search for budget-pacing frameworks (nothing beyond what the two sources already covered). Execution dimension: see google-ads-operations for the mechanics of applying a budget change.
Intake date: 2026-08-15
Known limits: The two-window rule and the 20% move cap are conventions chosen to suit a weekly cadence at this spend level, not results derived from data — a much larger or much smaller account should expect to retune both. Assumes reconciled numbers exist upstream; with unreconciled inputs the whole table is decoration. Covers no incrementality testing, which is the honest way to answer the question this table only approximates.
Assumed superseded: this skill reflects what research found at intake, not the best way that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than treating this as final.

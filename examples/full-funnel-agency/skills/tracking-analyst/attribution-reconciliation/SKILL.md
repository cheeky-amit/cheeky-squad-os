---
name: attribution-reconciliation
description: Use for the weekly reconciliation that every other seat's numbers depend on, and whenever a platform's reported results diverge from the store of record — produces one reconciled table and a root cause traced through change history.
---

# attribution-reconciliation

Source: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-auditor.md

Adapted from that agent's measurement-audit and change-history forensics capabilities —
the half of its 200-point checklist this squad routes to the measurement seat. The
structural half (account architecture, bidding, budget, creative coverage) was split off
into the media buyer's
[`paid-media-audit`](../../performance-media-buyer/paid-media-audit/SKILL.md); the two
skills are disjoint on purpose and together cover the original.

What was added, because the source assumes a one-off audit and this squad runs weekly:
a **standing reconciliation** and an explicit rule about which number is authoritative.
Without that rule, every seat quotes whichever platform flatters its own work, and the
weekly review becomes an argument about numbers rather than a decision made with them.

## The rule that settles arguments

**The store of record is authoritative for revenue and order count. Platforms are
authoritative for spend. Nothing else is authoritative for anything.**

Platform-reported conversions are an input to reconciliation, never an output of it.
Every number that leaves this seat is reconciled or is labelled `unreconciled` — and
labelled numbers may be used for direction, never for a spend decision.

## The weekly pass

Same window every week, same basis every week. Changing the basis mid-program destroys
the comparison the program is built on.

1. **Pull both sides.** Platform spend and platform-reported conversions per channel;
   store orders and revenue for the same window, on the same time zone.
2. **Align the basis.** Attribution window, click versus view, order versus transaction,
   gross versus net of returns and shipping. Write the basis at the top of the file every
   week — this is what makes week 9 comparable to week 2.
3. **Build the table.** One row per channel: spend, platform-reported conversions,
   attributed orders on the reconciled basis, revenue, cost per acquisition, and the
   variance between platform-reported and reconciled.
4. **Grade the variance.**
   - Within 3% — reconciled. Ship it.
   - 3% to 10% — flagged. Numbers ship labelled, root cause opens this week.
   - Above 10% — not reconciled. No spend decision may cite this row until it is
     resolved, and the studio-producer is told the same day, not on Monday.
5. **Sum-check.** Do the channels' attributed orders sum to more than the store's total?
   If so, the double count is real and is usually two platforms claiming the same order —
   name the overlap rather than pro-rating it silently.

## Root-causing a gap

Work in this order. It is ordered by how often each turns out to be the answer.

1. **Basis mismatch** — different windows, different time zones, different value bases.
   Cheapest and most common. Rule it out before touching anything technical.
2. **A change that landed.** Pull change history for the window on both sides: campaign
   edits, conversion-action edits, site or checkout releases, consent-banner changes.
   Correlate the gap's start date with the change list. A gap that starts on a Tuesday
   usually has a Tuesday deploy behind it.
3. **A tracking defect.** Only now hand to
   [`conversion-tracking-audit`](../conversion-tracking-audit/SKILL.md) and walk the
   affected path. Doing this first means auditing a stack to find a time-zone setting.
4. **A genuine attribution difference** — view-through, cross-device, modelled
   conversions. This is a real explanation, but it is the *last* one, because it is
   unfalsifiable and therefore the most comfortable place to stop looking.

Write which of the four it was. "Attribution differences" as a first answer is how a
tracking bug survives a quarter.

## Output

Write to `deliverables/measurement/weekly-reconciliation.md`, appending a dated section
each week: the basis, the table, the variance grade per channel, any open root cause with
its owner, and the one-line verdict the client brief quotes.

## Constraints

- Never restate a platform's own conversion figure as fact anywhere outside this file.
- Never change the basis to make a week look better. If the basis must change, change it
  going forward, say so in the file, and restate the prior week on both bases once.

## Done when

- The basis is written for this week.
- Every channel row has a variance grade.
- Every row above 3% has an open root cause with an owner and a category from the four
  above.
- The verdict line exists and is quotable without further explanation.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match), msitarzewski/agency-agents (paid-media-auditor.md — this skill, measurement and change-history-forensics half; its structural half went to performance-media-buyer), obra/superpowers (no match), web search for reconciliation procedures (finance-oriented material, adapted in spirit only). Execution dimension: see ga4-event-audit-operations for observing an event, and google-ads-operations for reading platform change history.
Intake date: 2026-08-15
Known limits: Single-basis reconciliation only: it settles arguments by declaring an authority rather than by modelling. It explicitly cannot tell you what was incremental — a channel can reconcile perfectly and still be claiming credit for demand that existed anyway, and nothing in this file addresses that. No media-mix or geo-holdout method. The variance grades (3% / 10%) are conventions, not derived thresholds.
Assumed superseded: this skill reflects what research found at intake, not the best way that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than treating this as final.

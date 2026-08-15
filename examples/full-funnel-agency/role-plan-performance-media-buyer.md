---
role: performance-media-buyer
created: 2026-08-17T09:04:12Z
status: active
---

# Engagement record — performance-media-buyer

## Task read

Own one budget across search, shopping, and paid social for week 1. Two things are due:
a structural audit of the inherited accounts before any spend decision, and the first
weekly pacing review. The squad goal binds acquisition cost to $58 or under by 2026-11-14
on at least $120,000 of monthly tracked spend; nothing this week is expected to move that
number, and the audit is what makes it movable later.

I do not own the conversion definitions and may not report an unreconciled number. My
Meta write path does not exist yet — that is declared on my role goal, not discovered here.

## Intended approach

1. Pull current state and 30-day change history for every entity in scope, both accounts,
   before proposing anything. (`google-ads-operations`, read-before-write.)
2. Run the structural audit on Google — architecture, bidding, budget, targeting, creative
   coverage. Route anything measurement-shaped to `tracking-analyst` rather than grading it.
   (`paid-media-audit`.)
3. Run the same structural checks against Meta from exported data; stage what cannot be
   applied.
4. Wait for the reconciled window from `tracking-analyst` before building the pacing table.
   Do not build it from platform reports first and "correct it later".
5. Build the pacing table, assign a constraint per row, apply the reallocation rule, and
   write the decision — including a decision not to move. (`budget-pacing-review`.)
6. Hand the fatigue list to `creative-strategist` and the pacing decision to
   `studio-producer`.

## Deliverables

- `deliverables/media/audit-google-ads-2026-08-18.md`
- `deliverables/media/pacing-2026-08-24.md`

## Assumptions

- [confirmed] The two-window rule in `budget-pacing-review` (require two consecutive 28-day windows at or under target before moving spend) is still the right call at this spend level. Step-further check taken: one doc lookup on the platform's current bid-strategy learning behavior, since a shorter learning period would justify a faster cadence. It has not changed — a strategy edit still re-enters learning, and a weekly reallocation on one window would keep campaigns learning permanently. Proceeding with the onboarded method.
- [confirmed] The 11 ad groups in audit finding C3 have no conversions in 60 days. Read directly from the reporting query, not from a summary view; re-read after the pause to confirm the write landed.
- [reported] Non-brand's target has never been set against its own performance, because brand and non-brand have shared a campaign since the account was built. This is the client's account history as told to Dana, not something I can observe in a 30-day change history window.
- [inferred] The 22:00–06:00 schedule suppression (note N2) costs roughly 9% of category search volume. Derived from the platform's own hourly distribution for the category, not from this account's data — the account has no data for those hours precisely because they are suppressed.
- [assumed] Meta spend can be reallocated on the same weekly cadence as Google despite being applied by hand. if wrong → the pacing decision ships on time but lands late on half the budget, and the 28-day comparison in week 3 straddles two different application dates.

## Amendments

- **2026-08-19.** Step 3 of the intended approach changed. I planned to stage Meta changes
  and hold them until the MCP server lands. Dana asked for them applied by hand instead, so
  the staged table became an instruction sheet with a rollback column rather than a queue.
  The work is the same; the delay is now a day rather than indefinite.
- **2026-08-21.** Step 5 was blocked and then unblocked in the same day. The reconciled
  window arrived with two of five rows marked not reconciled. I considered building the
  table on three rows and noting the gap, and rejected it: a pacing table missing the
  largest spend line is not a pacing table. Built the full table, marked the two rows, and
  let the reallocation rule fail on the evidence rather than pre-filtering the evidence to
  make it pass.

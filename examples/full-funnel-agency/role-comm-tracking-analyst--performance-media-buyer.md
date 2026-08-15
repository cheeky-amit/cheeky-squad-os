---
from: tracking-analyst
to: performance-media-buyer
created: 2026-08-21T16:32:05Z
status: ready
---

# Hand-off: tracking-analyst → performance-media-buyer

## What's ready

- `deliverables/measurement/weekly-reconciliation.md` — the reconciled table for the
  trailing 28 days, 2026-07-27 → 2026-08-23. Spend, platform-reported conversions,
  reconciled new customers, revenue, cost per acquisition, and a variance grade per row.
- `deliverables/measurement/tracking-audit-2026-08-19.md` — the conversion tracking audit
  that explains why three of the five rows are not clean.

## How to consume

Read the reconciliation first; read the audit only if you need the reason behind a grade.

Use the **Reconciled new customers** column for every cost-per-result figure in your pacing
table. Do not use **Platform-reported** for anything — it is in the table so the variance is
auditable, not so it can be quoted.

The grades map to what you may do with a row:

- `reconciled` (within 3%) — usable for a spend decision. One row this week: Meta retargeting.
- `flagged` (3–10%) — usable for direction, and it must carry the word *unreconciled*
  anywhere client-facing. Two rows: Google brand, Google non-brand.
- `not reconciled` (above 10%) — **may not carry a spend decision at all**, as source or
  destination. Two rows: Google Shopping/PMax, Meta prospecting.

The basis is stated at the top of the reconciliation and does not change week to week. If
you need a different window, ask rather than re-slicing it — a second basis in circulation
is how two people end up right about different numbers.

## Caveats

- **Meta prospecting is the largest spend line and the worst-graded row.** +83.0%, of which
  178 conversions are one order counted twice. Treat every historical Meta prospecting
  figure you have seen before this week as inflated by roughly the same shape.
- **Google Shopping/PMax's root cause is only half-identified.** Basis alignment closes
  about half the +11.4%; the residual is *suspected* view-through and modelled conversions
  and is not being written down as an attribution difference until it is confirmed. Due
  2026-08-28.
- **This is the first reconciled window.** There is no trustworthy prior window to compare
  against — the previous one came from platform reports. If your rule needs two consecutive
  windows, you have one.
- Brand and non-brand will both move when the store export switches from click date to
  order date. The change is staged, not applied; expect both variances to fall to near zero
  and neither row's real performance to have changed at all.

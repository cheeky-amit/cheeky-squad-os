# Weekly reconciliation — Kettleworks

Appended weekly by `tracking-analyst` using the `attribution-reconciliation` skill.
Newest section first. **This file is the authority.** Every other seat's numbers come from
here; nothing quotes a platform's own conversion figure directly.

---

## Week of 2026-08-17 — published 2026-08-21

### Basis (written every week, unchanged all program)

- **Window:** trailing 28 days, 2026-07-27 → 2026-08-23.
- **Authority:** store of record for orders and revenue; platforms for spend. Nothing else
  is authoritative for anything.
- **Attribution:** last non-direct click, order date, Europe/London, **net of returns**,
  new customers only (first order on the account).
- **Value basis:** gross of shipping, net of tax — documented for the first time this week
  (see [`tracking-audit-2026-08-19.md`](tracking-audit-2026-08-19.md), finding 3).

### The table

| Channel | Spend | Platform-reported | Reconciled new customers | Revenue | CAC | Variance | Grade |
|---|---|---|---|---|---|---|---|
| Google Search — brand | $9,600 | 431 | 412 | $79,104 | $23.30 | +4.6% | flagged |
| Google Search — non-brand | $31,200 | 394 | 372 | $67,704 | $83.87 | +5.9% | flagged |
| Google Shopping / PMax | $28,400 | 401 | 360 | $65,880 | $78.89 | +11.4% | **not reconciled** |
| Meta — prospecting | $34,800 | 421 | 230 | $41,400 | $151.30 | +83.0% | **not reconciled** |
| Meta — retargeting | $14,400 | 284 | 290 | $54,810 | $49.66 | −2.1% | reconciled |
| **Total** | **$118,400** | **1,931** | **1,664** | **$308,898** | **$71.15** | **+16.0%** | **not reconciled** |

### Sum-check

The channels' attributed orders sum to 1,664 against 1,664 in the store for the window —
no residual double count *after* reconciliation. Before reconciliation the platforms
collectively claimed 1,931, which is 267 orders that do not exist. 178 of those 267 are one
identified defect; see below.

### Root causes

Worked in the skill's order. The category is named for every open row, because
"attribution differences" as a first answer is how a tracking bug survives a quarter.

| Row | Category | Finding | Owner | Status |
|---|---|---|---|---|
| Meta — prospecting | **3. Tracking defect** | Ruled out basis mismatch (windows and time zone aligned) and change history (no campaign or site change correlates with the gap's start). Walked the path: browser pixel and server event share no deduplication key. 178 of 421 are the same order twice. | tracking-analyst → Kettleworks web team | Open, raised 2026-08-19 |
| Google Shopping / PMax | **1. Basis mismatch, partly** | Platform counts on click date; the store counts on order date. Aligning dates closes roughly half the gap. The residual is suspected view-through and modelled conversions — **not yet confirmed**, and it is not being written down as "attribution difference" until it is. | tracking-analyst | Open, due 2026-08-28 |
| Google Search — brand, non-brand | **1. Basis mismatch** | A one-day lag on the store export against the platform's click date. Explains the whole of both gaps; will close when the export moves to order date. | tracking-analyst | Fix staged |
| Meta — retargeting | — | Within bar. No investigation. | — | Closed |

### Verdict, quotable

> Blended new-customer acquisition cost is **$71.15** over the trailing 28 days on
> **$118,400** of tracked spend — against a $58 target and a $120,000 spend floor.
> Overall platform-versus-store variance is **+16.0%** against a 3% bar, so three of five
> rows cannot carry a spend decision this week. One defect explains 178 of the 267
> phantom orders and has an owner.

### Changes to the basis

None. First week; the basis above is the baseline every later week is compared against.

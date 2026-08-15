# Conversion tracking audit — Kettleworks

**Run:** 2026-08-19 · **Auditor:** tracking-analyst · **Skill:** `conversion-tracking-audit`
**Window observed:** 2026-08-17 → 2026-08-19, plus the trailing 28-day window 2026-07-27 → 2026-08-23 for count comparison.

> **Verdict: NOT SIGNED OFF.** Measured discrepancy **+16.0%** against a **3%** pass bar,
> and **178 confirmed double-counted events**. No number from Google Shopping/PMax or Meta
> prospecting may be cited in a spend decision until the blocking defect below is fixed.

---

## Pass bar (stated before the audit, not after)

| Criterion | Bar | Measured | Result |
|---|---|---|---|
| Platform-reported conversions vs store orders, same window and basis | within 3% | **+16.0%** | FAIL |
| Double-counted events on any browser + server path | zero | **178** | FAIL |
| Every optimizing conversion action has a documented value basis | all | 3 of 4 | FAIL |

---

## Path 1 — `purchase`, web, Google Ads

| Step | Result |
|---|---|
| 1. Event fires | PASS — fires on the order-confirmation state, not page load. Reload does not re-fire. |
| 2. Carries what it claims | PASS with note — value is **gross of shipping, net of tax**. Written down here for the first time; it was not documented anywhere before this audit. |
| 3. Browser and server agree | N/A — single client-side path. |
| 4. Consent respected | PASS — denied state suppresses marketing tags. Observed denial rate **11.3%**, stable across the three days observed. |
| 5. Definitions match across platforms | FAIL — see Path 4. Google and Meta count the same `purchase` under the same name on **different value bases**. |

## Path 2 — `purchase`, Meta browser pixel

| Step | Result |
|---|---|
| 1. Event fires | PASS |
| 2. Carries what it claims | **FAIL** — no order identifier on the browser event. There is nothing to deduplicate against. |
| 3. Browser and server agree | **FAIL** — see Path 3. |
| 4. Consent respected | PASS |
| 5. Definitions match | FAIL |

## Path 3 — `purchase`, Meta Conversions API (server)

| Step | Result |
|---|---|
| 1. Event fires | PASS — and it does fire for sessions where the browser path is blocked, so the server path is doing real work, not decorating. |
| 2. Carries what it claims | PASS — order identifier present and unique on this side. |
| 3. Browser and server agree | **FAIL — the blocking defect.** The two paths share no deduplication key: the server event carries the order id, the browser event does not. Every purchase that fires both is counted twice. |
| 4. Consent respected | PASS |
| 5. Definitions match | FAIL |

**Measured, over the 28-day window:** Meta prospecting reports **421** conversions.
**178** of those are the same order counted twice. Removing them leaves **243** against
**230** reconciled store orders — a residual **+5.7%**, consistent with view-through, which
is a real attribution difference rather than a defect.

## Path 4 — `newsletter_signup`, secondary

| Step | Result |
|---|---|
| 1. Event fires | PASS |
| 2. Carries what it claims | PASS — no value, correctly. |
| 5. Definitions match | **FAIL** — this action is set as a **primary** conversion on the Shopping/PMax campaign. That campaign's bid strategy is buying newsletter signups at purchase value. This is the finding `performance-media-buyer`'s audit routed here; it is confirmed. |

## Path 5 — subscription renewal

**Unverified.** Cannot be triggered by hand and there is no debug destination configured
for the server-side path. Sending a test event into the production stream to check would
poison a week of reporting, so it was not done. Unverified is the honest state; it is not
a pass.

---

## Findings, with first fix and owner

| # | Finding | Severity | First fix | Owner |
|---|---|---|---|---|
| 1 | Meta browser and server `purchase` events share no deduplication key — 178 double counts in 28 days | **Blocking** | Add the order id to the browser event as the shared deduplication key | Kettleworks web team (raised 2026-08-19) |
| 2 | `newsletter_signup` set as a primary conversion on Shopping/PMax | **Blocking** | Demote to secondary; re-baseline that campaign's target afterward | tracking-analyst, then performance-media-buyer |
| 3 | `purchase` value basis undocumented and inconsistent across platforms | High | Write the basis into the measurement plan and align both platforms to it | tracking-analyst |
| 4 | Subscription-renewal path unobservable | Medium | Configure a debug destination for server-side events | Kettleworks web team |

---

## What this means for everyone else this week

Under `attribution-reconciliation`'s authority rule, the store of record is authoritative
for revenue and orders. Until finding 1 is fixed:

- **Google Shopping/PMax (+11.4%)** and **Meta prospecting (+83.0%)** are **not reconciled**.
  No spend decision may cite them.
- **Meta retargeting (−2.1%)** is reconciled and usable.
- **Google brand (+4.6%)** and **non-brand (+5.9%)** are flagged: usable for direction,
  labelled in anything client-facing.

Full table in [`weekly-reconciliation.md`](weekly-reconciliation.md).

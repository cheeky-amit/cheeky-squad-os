# Paid media audit — Kettleworks Google Ads

**Run:** 2026-08-18 · **Auditor:** performance-media-buyer · **Skill:** `paid-media-audit`
**Window:** trailing 28 days, 2026-07-27 → 2026-08-23 · **Spend in scope:** $69,200 (Google only)

Structural audit. Tracking, tagging, and conversion-counting checkpoints are deliberately
absent — they are `tracking-analyst`'s
[`conversion-tracking-audit`](../measurement/tracking-audit-2026-08-19.md), and finding C2
below is routed there rather than graded here.

---

## First five moves

Ordered. The client brief quotes this list, not the body.

1. **Split brand out of the shared search campaign.** — performance-media-buyer, staged 2026-08-18
2. **Demote `newsletter_signup` from primary on Shopping/PMax.** — tracking-analyst (confirmed in their audit 2026-08-19)
3. **Pause the 11 zero-conversion ad groups.** — performance-media-buyer, staged
4. **Build the account-level negative list.** — performance-media-buyer, week 2
5. **Consolidate the six sub-threshold campaigns.** — performance-media-buyer, week 3, after 2 lands

---

## Critical — costing money now

### C1. Brand and non-brand share one campaign

**Observation.** One search campaign contains both branded and non-branded ad groups under
a single target. Brand converts at **$23.30** and non-brand at **$83.87**; blended across
the campaign's 784 new customers on $40,800, it reports **$52.04** and looks healthy.

**At stake.** $31,200 of 28-day non-brand spend is being managed against a number that
brand is holding up. The bid strategy cannot optimize what it cannot see separately.

**First action.** New campaign for brand, negative-keyword the brand terms out of the
non-brand campaign, re-baseline both targets after one learning period.
**Owner:** performance-media-buyer.

### C2. Shopping/PMax optimizes toward a signup, not a sale

**Observation.** The Shopping/PMax campaign's primary conversion action includes
`newsletter_signup`.

**At stake.** $28,400 of 28-day spend is bid against a mixture of purchases and email
addresses.

**First action.** Not graded here — a conversion-action change is `tracking-analyst`'s
surface, and changing it from this seat would silently invalidate their audit. **Routed**
2026-08-18; confirmed by them 2026-08-19 as their finding 2.
**Owner:** tracking-analyst.

### C3. $4,180 on ad groups with no conversion in 60 days

**Observation.** 11 ad groups across 3 campaigns, **$4,180** of 28-day spend, zero
conversions in 60 days.

**At stake.** $4,180 per 28 days, recurring. Roughly $54,000 annualized.

**First action.** Pause all 11. Nothing here needs a test first — 60 days is the test.
**Owner:** performance-media-buyer. Staged 2026-08-18, applied 2026-08-19.

---

## Structural — will cost money as spend scales

### S1. Six campaigns below the conversion threshold for their own bid strategy

Six campaigns earn fewer than 30 conversions per 30 days each and each runs its own
automated strategy. Below that volume a strategy cannot leave learning in a stable state.
**First action:** consolidate into two, by funnel stage. **Owner:** performance-media-buyer,
week 3 — after C1 lands, because the split changes which campaigns are sub-threshold.

### S2. No account-level negative keyword list

**$2,310** of 28-day non-brand spend went to queries with no purchase intent — repair
instructions, manufacturer support lookups, and a competitor's model number.
**First action:** build the account-level list; add the competitor term as a campaign-level
negative rather than account-level, since the comparison campaign wants it.
**Owner:** performance-media-buyer, week 2.

### S3. Fourteen ad groups with a single active ad

No creative test is possible in any of them. **First action:** hand the list to
`creative-strategist` as a coverage gap, not a fatigue request — these are not tired, they
are alone. **Owner:** performance-media-buyer → creative-strategist.

---

## Note — true, worth knowing, not worth a sprint

- **N1.** Naming convention encodes channel and product but not funnel stage, so every
  cross-campaign report is assembled by hand.
- **N2.** Ad schedule was set once in 2024 and never revisited; it suppresses 22:00–06:00,
  which is 9% of the category's search volume on the current data.

---

## Not audited, and why

- **Tracking, tagging, attribution, conversion counting** — `tracking-analyst`'s surface by
  design (see the skill's scope boundary).
- **Meta Ads** — the structural checks were run against exported data and are listed in
  [`pacing-2026-08-24.md`](pacing-2026-08-24.md) as staged changes. They could not be
  applied from this squad: no Meta Marketing API MCP server is connected. This is the
  declared capability gap on this role's goal.
- **Landing pages** — out of this squad's scope per the goal's Out of scope.

## Constraint honored

No finding in this audit proposes a promotional offer, discount, or price change. Several
of the queries in S2 would convert against one; the program does not do it, so the finding
is "exclude them", not "meet them with an offer".

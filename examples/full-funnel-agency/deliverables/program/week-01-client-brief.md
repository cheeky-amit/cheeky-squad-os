# Kettleworks — week of 2026-08-17

Published 2026-08-24 by studio-producer · Skill: `weekly-client-brief` · Brief 1 of 6

## Where we are against the goal

Blended new-customer acquisition cost is **$71.15** on **$118,400** of tracked spend over
the trailing 28 days — against a $58 target and a $120,000 floor by 14 November. It has not
moved yet, and it was not going to in week one: what week one bought was the ability to
measure it honestly, which we did not have on Monday.

## Decisions made this week

- **No budget moves between channels this week** — decided by Dana on 2026-08-24, on the
  evidence that only one channel has a single window of trustworthy numbers behind it and
  the rule needs two. Effective immediately; re-checked 2026-08-31.
  ([pacing review](../media/pacing-2026-08-24.md))
- **Eleven ad groups paused** — decided by Dana on 2026-08-19, on 60 days of zero
  conversions against $4,180 of 28-day spend. Applied 2026-08-19.
  ([audit, finding C3](../media/audit-google-ads-2026-08-18.md))
- **Brand split into its own search campaign** — decided by Dana on 2026-08-24, on the
  finding that brand's $23.30 cost per new customer was masking non-brand's $83.87 inside
  one blended target. Applied 2026-08-24; readable from 2026-09-07 once learning settles.
- **Winback message 3 rebuilt without an offer** — decided by Dana on 2026-08-20. The
  standard template closes on a discount; ours closes on a maintenance prompt built from
  the customer's own purchase date. ([sequence spec](../lifecycle/sequences/winback.md))

## Decisions waiting on you

- **Meta API access: chase the former contractor, or set up fresh credentials?** Needed by
  **2026-09-07**, because until it lands every Meta change is applied by hand — about 25
  minutes a week now, and it puts a day's delay into a 28-day comparison that the whole
  pacing method depends on. ([risk R1](risk-register.md))
- **Activate the winback sequence, or hold for the v2 segmentation?** Needed by
  **2026-08-29**. It is staged and deliverability-checked; activation is a send, and sends
  are yours to authorize. Holding costs one cohort of roughly 680 profiles per week.

## What changed in the work

- **Measurement.** The conversion tracking audit did not sign off. Platform-reported
  conversions are running **16.0% above** actual orders, and **178** of those in 28 days are
  one Meta purchase counted twice — the browser and server events share no deduplication
  key. Two of five channels cannot carry a spend decision until it is fixed.
  ([audit](../measurement/tracking-audit-2026-08-19.md))
- **Paid media.** Google account audited: three critical findings, three structural, two
  notes. First two moves applied.
- **Creative.** Four concepts live from 2026-08-21, each with a written hypothesis and a
  kill-or-scale threshold recorded before launch. First read 2026-08-28 — too early to say
  anything before then, and we will not.
  ([hook matrix](../creative/hook-matrix.md))
- **Lifecycle and organic.** Winback specified and staged. One organic brief written; the
  cannibalization check found two of your existing pages competing for the same query and
  that fix goes first.
  ([organic brief](../lifecycle/organic/burr-alignment-espresso.md))

## Risks that moved

- **R2 — the tracking fix is with your web team.** Raised 2026-08-19, no date back yet.
  If there is no deduplication key on the browser event by 2026-09-04, your largest spend
  line stays frozen — not because it is failing, but because nobody can prove what it is
  doing. Owner: your web lead. Pre-agreed response: escalate with the phantom-order count.
- **R1 — Meta access.** Trigger date 2026-09-07. See the waiting decision above.

## Next week

1. **Second reconciled window closes 2026-08-31** — first legitimate pacing move becomes
   possible if retargeting holds. Owner: performance-media-buyer.
2. **First creative read 2026-08-28** — four cells against their own criteria. Owner:
   creative-strategist.
3. **Account-level negative keyword list.** $2,310 per 28 days of non-converting queries.
   Owner: performance-media-buyer.

---

*Every number above is reconciled against your store of record, not taken from an ad
platform's own reporting. Where a figure is not yet reconciled it is not in this brief.*

# Winback

**Author:** lifecycle-organic-marketer · **Skill:** `lifecycle-sequence-spec`
**Status:** specified 2026-08-20, staged in the platform 2026-08-21, **not yet live** — awaiting Dana's approval on the message-3 angle.

This is the sequence where the program's Out-of-scope constraint does real work. The source
material's winback template closes on an incentive; this program does not run one. What
replaced it is below, under "The incentive replacement".

---

## Trigger

- **Event:** no purchase in 210 days, evaluated daily, on profiles with at least one prior order.
- **Delay:** immediate on qualification.
- **Suppression at entry:** anyone in the post-purchase or review sequences; anyone who
  ordered in the last 30 days on a second profile matched by email; anyone with an open
  support ticket.

## Segment

- **Entry definition:** lifecycle stage = `lapsed customer` **and** last order ≥ 210 days
  **and** marketing consent = granted **and** hard-bounce = false.
  Three attributes; the skill's floor is two.
- **Estimated size:** **14,280** profiles as of 2026-08-20.

## Messages

| # | Channel | Delay from entry | Job of this message | Primary link |
|---|---|---|---|---|
| 1 | Email | 0 days | Re-establish who we are with one useful thing: how to tell when burrs are due for replacement. | `/guides/burr-life` |
| 2 | Email | 5 days | Show what changed in the range since they last bought — new, not "better". | `/whats-new` |
| 3 | Email | 12 days | The maintenance prompt: at their purchase date, their burrs are near end of rated life. Includes the replacement part for their exact model. | `/parts/finder` |

One primary link per message. No message carries a second call to action.

## Exit conditions

All five are named. A sequence with no maximum duration will eventually mail someone forever.

- Converted — `placed_order` fires.
- Unsubscribed or opted out.
- Hard bounce or delivery failure.
- Entered a higher-priority sequence (post-purchase wins over this one).
- **Maximum duration: 21 days.** Exit regardless of state.

## Success bar

- **Primary:** click-through ≥ **3.2%** across the sequence.
- **Secondary:** revenue per recipient ≥ **$0.41**.
- **Reads on:** 2026-09-18 — 21 days of sends plus one full attribution window after the
  last cohort exits.

Open rate is not a criterion and does not appear in the reporting for this sequence.

## Compliance

- **Consent basis:** checkout opt-in or form double opt-in, both recorded with date, method,
  and source on the profile. Profiles from the 2024 list import are **excluded** — the
  consent record for that import is incomplete, and the correct answer to an incomplete
  consent record is not to mail it.
- **Sender:** marketing sender. Never the transactional pool.
- **Deliverability precondition:** checked 2026-08-20 before staging — authentication
  records in place, complaint rate 0.04% against a 0.30% hard limit, hard bounces removed on
  detection. The sequence would not have been staged without this.

---

## The incentive replacement

The source template's message 3 is a percentage-off offer. That is out of scope for this
program in every channel, so message 3 had to earn the reopen a different way.

**What it does instead:** it uses a fact the profile already contains — the purchase date —
to tell the customer something true and specific about their own equipment. Burrs have a
rated life in kilograms; a customer 210+ days past a grinder purchase at typical household
volume is approaching the point where grind consistency drifts. The message says that, names
the replacement part for their exact model, and links to the part finder.

Why this is the harder and better version:

1. **It is useful whether or not they buy.** An incentive is only useful if they buy.
2. **It is personalized by data we already hold**, not by a discount tier.
3. **It does not train the list to wait for an offer**, which is the compounding cost of
   incentive-led winbacks and the reason the constraint exists.

**Open risk, stated:** it assumes typical household volume. For a light user the prompt
arrives early and reads as a sales pitch. Mitigation staged for v2 — segment on lifetime
bean spend where the data exists. Flagged to Dana as the one thing to watch in the first
read on 2026-09-18.

## Changelog

- **2026-08-20** — specified. Message 3 replaced the source template's incentive close.
- **2026-08-21** — staged in the platform via `klaviyo-flow-operations`; read-back matched
  the staged table. Not activated: activation is a send, and a send is Dana's to authorize.

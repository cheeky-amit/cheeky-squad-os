---
name: klaviyo-flow-operations
description: Use when actually operating the email and SMS platform — reading what flows and segments exist, pulling flow performance, checking a profile's sequence membership, or staging a change to a live flow. The mechanics of touching a running lifecycle program without breaking it.
---

# klaviyo-flow-operations

Source: https://developers.klaviyo.com/en/reference/api_overview
Also drawn from: https://developers.klaviyo.com/en/reference/get_flows

Distilled from the platform's own API reference. The knowledge skill in this seat
specifies what a sound sequence looks like; this one is how you inspect and change a
*running* one, and which changes are safe to make while people are inside it.

## Read the live state before proposing anything

A lifecycle program on paper and the one that is actually sending diverge within a
quarter, always. Before any recommendation:

- **List the flows that exist and their status.** Live, draft, and manually-stopped are
  three different things, and a "live" flow with every message paused sends nothing while
  looking healthy in a summary.
- **List the segments and lists each flow triggers from**, with current membership
  counts. A sequence targeting a segment of eleven people is not a program, and no amount
  of copy work will change that.
- **Pull per-message performance for the flow**, not just flow totals. A flow's aggregate
  hides the one message where everyone leaves.
- **Check for overlap.** A profile eligible for three sequences at once is the most common
  cause of a complaint spike, and it is invisible from any single flow's view.

## Changing a live flow

The governing fact: **people are inside the sequence right now**, at different steps, and
a change lands differently depending on where they are.

1. **Adding a message at the end** is the safest change — nobody has passed it yet.
2. **Editing an existing message's content** applies to everyone who has not yet received
   it. This is usually what you want and rarely what people expect.
3. **Changing a delay** changes the schedule for profiles mid-sequence. Shortening a delay
   can fire two messages close together for people who were already waiting.
4. **Changing the trigger or entry filter** does not retroactively remove anyone already
   inside. Expect a tail of profiles moving through the old logic.
5. **Adding an exit condition** takes effect at the next evaluation point, not
   immediately.

Stage every change the same way the media seat stages a budget change: a table of what
changes, from what to what, and what happens to profiles currently mid-sequence. That
last column is the one people forget and the one that generates the complaint.

## Send-safety rules

- **Never trigger a send, campaign, or flow message to a real audience from this skill.**
  Read, inspect, stage, and hand the send to the human who owns it. This is a bright line,
  not a preference — an accidental send cannot be recalled.
- **Preview and test sends go to a seeded internal address**, never to a segment.
- **Check suppression and consent state before proposing an audience expansion.** A
  profile that unsubscribed, bounced hard, or never consented is not addressable, and
  counting it in a projected reach is how a plan promises revenue that cannot exist.
- **Respect the quiet-hours and frequency settings already configured.** If a proposal
  requires changing them, that is its own decision with its own approval, surfaced
  separately.

## Reading performance honestly

- **Pull click-based metrics.** Open rates on this platform are inflated by
  privacy-preserving mail clients, exactly as the knowledge skill says; the API will
  happily hand you an open rate that means nothing.
- **Attribute revenue on the platform's own attribution window, and say which window you
  used.** It will not match the store's last-click view, and the difference is not an
  error — it is two definitions. The tracking-analyst's reconciliation is where that gets
  settled; do not silently pick whichever is higher.
- **Per-message, per-variant, per-segment** — a flow-level number cannot tell you which
  of the three to change.

## Constraints worth knowing

- **Rate limits are per endpoint class.** A profile-by-profile loop over a large segment
  will be throttled; use the bulk read paths for anything above a few hundred.
- **Profile writes are upserts.** Writing a partial profile can clear expectations about
  fields you did not send. Read, merge, then write.
- **Deleting a flow is not reversible** and takes its historical reporting with it.
  Archive or deactivate instead; there is no version of this program where deleting is the
  right call.

## Escalate rather than improvise

Stop and surface when: a change would alter consent handling or suppression logic; a flow
would send to an audience larger than the last agreed size; the platform returns an
authorization error on a write; or the change requires editing a segment another sequence
also triggers from.

## Scope boundary

This skill touches the platform. [`lifecycle-sequence-spec`](../lifecycle-sequence-spec/SKILL.md)
decides what the sequence should be, and every field it requires must be filled before
anything gets staged here. Organic search is unrelated to this surface — see
[`organic-search-brief`](../organic-search-brief/SKILL.md).

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match),
msitarzewski/agency-agents (knowledge-dimension match only: marketing-email-strategist
covers sequence design and names several platforms, but documents no platform's
mechanics), obra/superpowers (no match), Klaviyo API overview
(https://developers.klaviyo.com/en/reference/api_overview — primary source), Klaviyo
flows reference (https://developers.klaviyo.com/en/reference/get_flows), MCP server
registries (a Klaviyo MCP server exists and is connected in this project at intake, which
is why this seat has an execution skill and no declared gap).
Intake date: 2026-08-15
Known limits: no endpoint paths, parameter names, or API revision dates are reproduced —
they change and a stale signature is worse than none; re-read the live reference before
any call. Covers this one platform only; a squad on a different ESP needs a different
execution skill, not an adaptation of this one. Says nothing about template design or
deliverability infrastructure (authentication records, warm-up), both of which sit outside
this skill and partly outside this squad.
Assumed superseded: this skill reflects what research found at intake, not the best way
that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than
treating this as final.

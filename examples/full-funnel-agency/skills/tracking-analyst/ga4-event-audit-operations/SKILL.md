---
name: ga4-event-audit-operations
description: Use when actually inspecting or proving tracking behavior — watching an event fire in real time, checking what parameters arrived, confirming browser and server events deduplicate, or reproducing a consent state. The mechanics of observing what the site really sends.
---

# ga4-event-audit-operations

Source: https://developers.google.com/analytics/devguides/collection/ga4
Also drawn from: https://support.google.com/analytics/answer/7201382 (DebugView), https://developers.google.com/analytics/devguides/collection/protocol/ga4 (Measurement Protocol), and https://developers.facebook.com/docs/marketing-api/conversions-api

Distilled from the platforms' own collection documentation. The knowledge skill in this
seat says what a sound conversion path looks like; this one is how you *observe* whether
this site actually behaves that way, in what order to look, and which observations are
trustworthy.

## The ordering rule that saves the afternoon

Observe in this order, and stop at the first place the story breaks:

1. **The page's own data layer** — what the site says it is sending.
2. **The tag manager's preview** — what the container decided to do with it.
3. **The analytics real-time debug view** — what actually arrived, with parameters.
4. **The ad platform's own event tool** — what that platform received and matched.
5. **The store of record** — whether an order exists at all for the session.

Going in the other direction — starting from the platform's reported number and working
back — is how a whole day gets spent proving something that was never sent.

## What to capture, per event

For every conversion event under audit, capture and write down:

- **Event name**, exactly as it arrives, including case. Case-sensitive mismatches are
  invisible in a dashboard and fatal in a report.
- **Every parameter**, with its value and type. A value that arrives as a string where a
  number is expected is silently dropped by some consumers and coerced by others.
- **The deduplication key** — the identifier the browser event and the server event share.
  No shared key means no deduplication, no matter what either platform's UI claims.
- **The timestamp and the time zone.** Half of all reconciliation gaps live here.
- **The consent state at the moment of firing.**

## Proving deduplication, not assuming it

The single most common false pass in this audit is a browser and a server event that
both report success and are counted twice.

- Fire one real conversion and capture both events with their identifiers side by side.
- Confirm the identifiers match exactly — not "look similar", not "both derive from the
  order id".
- Then check the platform's own reported count for that window against the number of
  real conversions. Two is the answer you are trying to rule out.
- Where a server-side path exists, confirm it fires **for sessions where the browser path
  is blocked**. A server path that only fires alongside a working browser path adds
  nothing except double-counting risk.

## Reproducing consent states

Never audit consent by reading the banner's configuration. Reproduce it:

- Granted: everything expected fires.
- Denied: the marketing events do not fire, and whatever still fires is supposed to.
- No choice made yet: usually the most revealing state and the one nobody tests.

Record the observed denial rate from real traffic. A drifting denial rate is a
conversion trend with no marketing cause, and it will be misread as one.

## When you cannot observe directly

Some paths cannot be triggered by hand — a subscription renewal, a fulfillment webhook,
an offline import. For these:

- Use the platform's server-side collection endpoint to send a **clearly marked test
  event** into a debug destination, never into the production stream. Sending test
  traffic into a production property to see if it arrives is how a week of reporting gets
  poisoned.
- If a debug destination is unavailable, say the path is **unverified** in the audit
  output. Unverified is a legitimate finding; assumed-working is not.

## Constraints worth knowing before you promise a timeline

- **Real-time debug surfaces lag and sample.** An event missing from a debug view for a
  few seconds is not yet evidence of absence.
- **Reporting tables are not real-time.** Reconciling against a report before its
  processing window closes produces a discrepancy that fixes itself overnight, and a
  root-cause investigation that never should have started.
- **Some platform tools show only matched events**, not received-and-dropped ones. A
  clean view can mean "nothing arrived" as easily as "everything is fine".

## Escalate rather than improvise

- Never change a tag, trigger, or container configuration from this skill. Observation
  only. A fix goes to whoever owns the site, with the observation attached.
- Never send test events into a production data stream.
- If observing requires a credential this role does not have, say so and stop — do not
  route around it.

## Scope boundary

This skill observes. [`conversion-tracking-audit`](../conversion-tracking-audit/SKILL.md)
decides what a sound path is and issues the verdict;
[`attribution-reconciliation`](../attribution-reconciliation/SKILL.md) does the weekly
numbers and the root-cause order that sends you here in the first place.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match —
closest is web-performance instrumentation, different problem), msitarzewski/agency-agents
(knowledge-dimension match only: its tracking-specialist agent lists capabilities but
does not document observation mechanics), obra/superpowers (no match), GA4 collection
docs (https://developers.google.com/analytics/devguides/collection/ga4 — primary source),
GA4 DebugView support documentation
(https://support.google.com/analytics/answer/7201382), GA4 Measurement Protocol
(https://developers.google.com/analytics/devguides/collection/protocol/ga4), Meta
Conversions API docs
(https://developers.facebook.com/docs/marketing-api/conversions-api), MCP server
registries (no analytics MCP server connected in this project at intake).
Intake date: 2026-08-15
Known limits: deliberately names no UI element, menu path, or parameter name — those
change and a stale click-path is worse than none. Covers GA4 and Meta's conversion
surfaces; other platforms' event tools are not covered. Observation only: contains
nothing about implementing or fixing a tag, which is site-engineering work outside this
squad's ownership. Assumes analytics and tag-manager read access already exists.
Assumed superseded: this skill reflects what research found at intake, not the best way
that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than
treating this as final.

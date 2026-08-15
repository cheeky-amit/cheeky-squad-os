---
name: conversion-tracking-audit
description: Use before trusting any conversion number — at program start, after any site or checkout change, and whenever a platform and the store disagree. Verifies each conversion path end to end against a stated pass bar.
---

# conversion-tracking-audit

Source: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-tracking-specialist.md

Adapted from that agent's tag management, event design, and debugging capabilities. The
source's central claim is the one worth carrying: bad tracking is worse than no
tracking, because a miscounted conversion actively teaches the bidding algorithm to
optimize for the wrong thing.

What changed: the source is organized by *technology* (tag manager, analytics platform,
each ad platform's own pixel). This is organized by **conversion path**, because a
discrepancy is never located in a technology — it is located where two technologies
disagree about one event. Walking the path finds it; walking the tech stack finds
everything except it.

## Precondition

Get the list of conversion actions each platform is currently optimizing toward, and the
store's own order record for the same window. Without both sides, this is not an audit,
it is a tour.

## Walk each path

For every conversion action any campaign optimizes toward, walk it end to end. One pass
per action, not one pass per platform.

### 1. The event fires

- Does it fire on the real completion state, or on a page load that also happens on
  refresh, back-navigation, and direct URL entry?
- Does it fire exactly once per completion? Reload the confirmation state and watch.
- Is the trigger tied to something durable, or to a CSS selector one redesign from
  breaking?

### 2. The event carries what it claims

- Value present, numeric, and in a stated currency.
- Order identifier present and genuinely unique — this is the deduplication key, and
  everything below depends on it.
- Items, quantities, and any parameter a report or bid strategy consumes.
- Is value net or gross of shipping, tax, and returns? Write down which. Half of all
  "attribution problems" are this question, unanswered.

### 3. Browser and server agree

- Where the same event is sent both client-side and server-side, confirm they share the
  same deduplication key, and confirm deduplication actually happens — count both sides
  for a day and compare.
- Confirm the server-side path fires for sessions where the browser path is blocked;
  if it does not, the server-side path is decorative.

### 4. Consent state is respected

- With consent granted: everything fires.
- With consent denied: the marketing events do not fire, and the ones that still do are
  the ones that are supposed to.
- Record the observed denial rate. A shifting denial rate is a conversion trend that has
  nothing to do with marketing, and it will be misread as one.

### 5. The definitions match across platforms

- Same event name, same trigger, same value basis on every platform. A platform counting
  a different thing under the same name is the most expensive defect on this list,
  because nothing about it looks broken.
- Primary versus secondary designation: is anything optimizing toward a micro-conversion
  by accident?

## The pass bar

Stated up front, so the audit ends in a verdict rather than a discussion:

- **Platform-reported conversions versus store orders: within 3%** for the same window
  and the same attribution basis. Above 3%, tracking is not signed off, and the number
  does not go in the client brief without the word *unreconciled* next to it.
- **Zero double-counted events** on any path sending both browser and server events.
- **Every optimizing conversion action has a documented value basis.**

## Output

Write to `deliverables/measurement/tracking-audit-<YYYY-MM-DD>.md`: one section per
conversion path with a pass or fail against each of the five steps, the measured
discrepancy, and — for every fail — the specific first fix and its owner.

## Scope boundary

This skill establishes whether numbers can be trusted. Reconciling them week to week and
root-causing a gap that appears later is
[`attribution-reconciliation`](../attribution-reconciliation/SKILL.md). Account
structure, bidding, and creative coverage are the media buyer's
[`paid-media-audit`](../../performance-media-buyer/paid-media-audit/SKILL.md) — this
skill does not grade any of them, and that split is deliberate: they were one 200-point
checklist in the source and are two seats here.

## Done when

- Every optimizing conversion action has been walked through all five steps.
- The discrepancy figure is measured, not estimated.
- Every fail has a named first fix and an owner.
- The verdict is stated: signed off, or not signed off with the blocking defect named.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match), msitarzewski/agency-agents (paid-media-tracking-specialist.md — this skill, reorganized from technology-first into a per-conversion-path walk), obra/superpowers (no match), web search for tracking audit procedures (vendor content, mostly product marketing). Execution dimension for this seat was researched separately and produced ga4-event-audit-operations.
Intake date: 2026-08-15
Known limits: The 3% pass bar is a working convention for this program, not an industry standard — a business with heavy offline or subscription revenue should expect to set it differently and say why. Covers web conversion paths; app, in-store, and call tracking are out. Names no platform UI or parameter, so it tells you what to check and not where to click.
Assumed superseded: this skill reflects what research found at intake, not the best way that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than treating this as final.

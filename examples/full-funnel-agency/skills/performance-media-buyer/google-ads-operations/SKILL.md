---
name: google-ads-operations
description: Use when actually operating the Google Ads account — pulling a report, reading change history, applying a budget or bid-strategy change, or staging a bulk edit. The mechanics of making a change land, as distinct from deciding what change to make.
---

# google-ads-operations

Source: https://developers.google.com/google-ads/api/docs/start
Also drawn from: https://developers.google.com/google-ads/api/docs/reporting/overview and https://developers.google.com/google-ads/scripts/docs/start

Distilled from Google's own API and Scripts documentation. Nothing here is a framework —
this is the execution layer. The knowledge skills in this seat decide *what* should
change; this one is how the change gets made, verified, and rolled back, and what the
platform will refuse to let you do.

## Pick the right instrument

Three ways to act on the account. Choosing wrong is where an afternoon goes.

| Need | Use | Why |
|---|---|---|
| Read anything — performance, settings, change history | Reporting query (GAQL) | One query, structured result, no UI drift |
| A change across many entities at once | Bulk upload / staged edit | Reviewable before it applies; one undo unit |
| A recurring scheduled read or nudge | Ads Script | Runs in-account on a schedule with no external host |
| A one-off change to a handful of entities | The UI | Below roughly 20 entities, tooling costs more than it saves |

## Reading before writing

Every write in this account starts with a read that proves the current state. The rule
is not caution for its own sake — a bid-strategy target changed against a stale reading
of conversion volume is the single most expensive reversible mistake in paid search.

- **Pull the current state of exactly the entities you are about to touch**, not a
  summary. Ids, names, current values.
- **Pull change history for the same entities over the last 30 days** before proposing a
  change. If someone already changed this last week, that is a conversation, not a
  conflict to resolve unilaterally. Change history is also the first place to look when
  a reconciliation gap appears on a specific date — the tracking-analyst's root-cause
  order sends you here.
- **Check the conversion actions the entity optimizes toward.** A target set against a
  conversion definition that has since changed is a stale target wearing a current
  number.

## Applying a change safely

1. **Stage it.** Write the intended change out as a table — entity id, field, current
   value, new value, reason — before touching the platform. This table is the record;
   the platform's own change log is the confirmation.
2. **One dimension at a time.** Do not change budget and bid target in the same pass on
   the same campaign. When performance moves, you will not know which one moved it, and
   the platform's learning behavior makes the confound permanent for that period.
3. **Respect the learning period.** After a bid-strategy change, the campaign re-enters
   learning. Repeated target edits keep it there indefinitely. Note the change date and
   do not read results before the learning window closes.
4. **Verify by reading back.** After the write, re-query the same entities and diff
   against your staged table. A write that returned success and did not land is a real
   failure mode, most often a validation the API accepted at the request level and
   rejected at the entity level.
5. **Record the rollback.** The "current value" column of your staged table *is* the
   rollback plan. Keep it.

## Constraints the platform imposes

Know these before promising a client anything:

- **Budget changes take effect on the platform's own daily cycle**, not instantly — the
  same-day spend figure after a budget change is not evidence of anything.
- **Removed entities are not deleted.** They stay queryable and keep their historical
  data. This matters when reconciling a window that spans a restructure.
- **Rate and quota limits apply per developer token and per account.** Batch reads
  rather than looping single queries; a rate-limited job that half-completed is worse
  than one that never started.
- **Some fields are immutable after creation** — campaign type and certain bid-strategy
  transitions among them. When a change is impossible, the answer is a new entity plus a
  migration plan, not a workaround.

## Escalate rather than improvise

Stop and surface, do not proceed, when:

- The staged change would exceed the week's agreed budget envelope.
- A read-back diff does not match the staged table after one retry.
- The change requires creating or modifying a conversion action — that is the
  tracking-analyst's surface, and changing it here silently invalidates their audit.
- The account returns an authorization error on a write. Never fall back to the UI to
  work around a permission the credential does not have; the permission boundary is the
  point.

## Scope boundary

This skill does not decide what to change —
[`budget-pacing-review`](../budget-pacing-review/SKILL.md) does, and
[`paid-media-audit`](../paid-media-audit/SKILL.md) decides whether the container
deserves the money. It also covers Google only. Meta is a **declared capability gap** for
this role (see the role goal's `## Declared capability gaps`): the account can be read
from exports, but nothing can be pushed until a Meta Marketing API MCP server is
connected.

## Provenance & limits

Sources searched: anthropics/skills (no match — no advertising-platform content),
addyosmani/agent-skills (no match), msitarzewski/agency-agents (knowledge-dimension
matches only; its paid-media agents describe strategy and mention API access without
documenting the mechanics), obra/superpowers (no match), Google Ads API official docs
(https://developers.google.com/google-ads/api/docs/start — this skill's primary source),
Google Ads reporting overview
(https://developers.google.com/google-ads/api/docs/reporting/overview), Google Ads
Scripts docs (https://developers.google.com/google-ads/scripts/docs/start), MCP server
registries (searched for a Google Ads MCP server — none connected in this project at
intake).
Intake date: 2026-08-15
Known limits: no endpoint signatures, field names, or API version numbers are reproduced
here on purpose — they change per release and a stale signature in a skill file is worse
than no signature. Re-read the live reference before writing a query. Covers Google Ads
only; Meta, Microsoft, and Amazon are out. Assumes credentialed API or Scripts access
already exists; it does not cover obtaining a developer token or completing OAuth.
Assumed superseded: this skill reflects what research found at intake, not the best way
that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than
treating this as final.

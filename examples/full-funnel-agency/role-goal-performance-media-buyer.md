---
parent: .squad/goal.md
role: performance-media-buyer
created: 2026-08-15T08:31:07Z
---

# Role goal — performance-media-buyer

Hold one budget across search, shopping, and paid social, and move it on written
evidence: audit the inherited accounts before spending in them, publish a weekly pacing
decision (including a decision not to move spend), and keep blended new-customer
acquisition cost tracking toward $58 or under on at least $120,000 of monthly tracked
spend by 2026-11-14.

## Owned outputs

- `deliverables/media/audit-<account>-<YYYY-MM-DD>.md` — the structural pre-flight per
  inherited account, findings graded and owned.
- `deliverables/media/pacing-<YYYY-MM-DD>.md` — the weekly table, the constraint per row,
  and the reallocation decision with its two-window evidence.
- `.squad/workspaces/performance-media-buyer/**` — sandbox: raw exports and working
  pacing files, never the deliverable itself.

## Hand-offs

- `studio-producer`: the weekly pacing decision line, verbatim and quotable, plus any
  spend commitment that belongs in the risk register.
- `creative-strategist`: the fatigue list — assets whose frequency is climbing and
  click-through declining — as a refresh request, with the date the decline started.
- `tracking-analyst`: consumed, not produced — this role may not report a number that has
  not been reconciled.

## Stop conditions

- `needs:` the reconciled weekly numbers exist at
  `deliverables/measurement/weekly-reconciliation.md` and cover the current 28-day window.
- `needs:` the provisioned workspace at `.squad/workspaces/performance-media-buyer` exists.
- `stop:` a proposed change would require promotional, discount, or price-led messaging —
  excluded by the squad goal.
- `stop:` a staged change does not match on read-back after one retry, or the platform
  returns an authorization error on a write.

## Declared capability gaps

- `performance-media-buyer` operates Meta Ads, but no execution skill was found or
  approved for it. Declaring this as a capability gap: no MCP server is connected for the
  Meta Marketing API, so the account can be read from manual exports but no change can be
  pushed from this squad. Proposed via `squad-env`'s `global_needs`: connect a Meta
  Marketing API MCP server, for Dana to approve. Until it lands, every Meta change is
  staged here as a table and applied by a human in the platform.

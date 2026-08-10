# ADR 0001: Separate execution cadence from export destination

- Status: accepted
- Date: 2026-08-08

## Decision

Keep `one-time`, `multi-use`, and `evergreen` as execution cadence. Represent where a
snapshot is made available with a separate `destination` field: `session`, `project`,
`user`, or `plugin`.

The v2 manifest records both values. Provider adapters may vary dispatch behavior by
cadence, but path and confirmation policy is selected only by destination.

## Consequences

- Existing goals and legacy rosters keep their current mode semantics.
- Adding an export target never creates a fourth cadence.
- Session exports can have an empty write set; user exports can require a stronger
  confirmation without changing how the squad executes.

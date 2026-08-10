# ADR 0002: Export vendored snapshots with one runtime owner

- Status: accepted
- Date: 2026-08-08

## Decision

An exported squad is an immutable, content-addressed snapshot until the creator runs an
explicit re-export. It must not import code from the generator at runtime.

When both providers are selected, the manifest names exactly one `runtime_owner`. That
provider owns shared lifecycle behavior, while both provider adapters may compile role
and discovery artifacts. This prevents duplicate hooks from processing one event twice.

Legacy rosters are migrated only in memory. Existing files are not rewritten, relocated,
or renamed without a preview and matching confirmation.

## Consequences

- Generated packages vendor the scripts, templates, skills, and role inputs they need.
- A plan is bound to exact source and output hashes; stale confirmations cannot apply.
- Re-export and uninstall can be receipt-driven rather than guessing ownership.

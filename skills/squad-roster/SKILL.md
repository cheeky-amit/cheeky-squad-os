---
name: squad-roster
description: Use when the user wants to inspect, modify, audit, validate, or export the active squad — phrases like "show the roster", "who's on the squad", "remove <role>", "audit scopes", "export this squad", "make this project/user/session portable", "build a Claude/Codex plugin", or "uninstall the exported squad". Owns the canonical provider-neutral .squad/roster.json, its human view, and the preview/confirm lifecycle for squad-export.
version: 1.1.0
author: cheeky-squad-os
license: MIT
compatible-with: [claude-code, codex, agentskills-1.0]
---

# squad-roster

You own `.squad/roster.json`, the source of truth for roles, and regenerate
`.squad/roster.md` after every roster write. Version 2 is provider-neutral. Legacy
Claude rosters remain readable through pure, deterministic in-memory migration.

You also expose **export** as a verb on this existing lifecycle skill. Export compiles
roles; it never authors a second roster and never installs or enables a plugin.

## Canonical roster v2

```json
{
  "schema_version": 2,
  "squad_goal_ref": ".squad/goal.md",
  "execution_mode": "one-time",
  "created": "<ISO-8601>",
  "roles": [
    {
      "id": "report-writer",
      "purpose": "Write the verified final report",
      "description": "Use when the squad needs its verified final report",
      "file_ownership": {
        "include": ["reports/final/**"],
        "exclude": []
      },
      "capabilities": ["filesystem.read", "filesystem.write"],
      "reasoning": {"profile": "deep", "effort": "high"},
      "active": true,
      "goal_ref": ".squad/role-goal-report-writer.md",
      "provider_overrides": {
        "claude": {
          "model": "opus",
          "tools": ["Read", "Write"],
          "agent_file": ".claude/agents/report-writer.md"
        }
      },
      "created": "<ISO-8601>"
    }
  ]
}
```

Portable capabilities include `filesystem.read`, `filesystem.glob`,
`filesystem.search`, `filesystem.write`, `filesystem.edit`, `shell.execute`,
`network.fetch`, `network.search`, and `notebook.edit`. Exact provider-only tools use
`provider_overrides`; do not invent a neutral mapping.

An optional `environment` carries `workspace`, `directories`, `variables`, `context`,
and `tools`. Provider overrides may tune Claude model/tools/legacy agent path or Codex
model/reasoning/sandbox. They do not replace purpose, description, or ownership.

## Legacy behavior

When the roster has no `schema_version: 2`, load it through the deterministic migration
path. Present the canonical in-memory result, but do not rewrite, relocate, or rename the
legacy roster or existing `.claude/agents/` files automatically.

Before any conversion write, preview the exact write/delete set and require the matching
confirmation. Declining leaves the existing squad byte-for-byte untouched.

## Read operations

### List

1. Read and canonicalize `.squad/roster.json`. If absent, say: *"No roster. Run
   `/cheeky-squad-os:squad-onboard` to start a squad."*
2. Print role ID, purpose, reasoning profile, active state, and first ownership path.
3. Print execution cadence and schema source (`v2` or `legacy, migrated in memory`).

### Detail

For one role, print purpose, description, all include/exclude ownership paths,
capabilities, reasoning, environment, provider overrides, goal reference, active state,
and creation time. Read referenced files only when present; absence is not permission to
guess their contents.

### Audit ownership

Print every include/exclude mapping and flag overlaps. For Codex, label ownership
**instructional in v1**. For Claude, say whether the active runtime actually owns the
PermissionRequest hook; do not make a mechanical claim from the roster alone.

The legacy Claude `.squad/` structural reservation remains runtime-specific. Never
describe it as portable or as Codex enforcement.

## Write operations

### Add

Called by `squad-role` after role generation:

1. Canonicalize the roster in memory.
2. Refuse an ID collision.
3. Validate required neutral fields and optional provider overrides.
4. Append the role, pretty-print v2 JSON, and regenerate `.squad/roster.md`.
5. Report every generated provider artifact separately from the neutral roster write.

### Deactivate or remove

Ask whether to soft-deactivate (`active: false`) or hard-delete the roster entry and
referenced generated role/goal artifacts. Hard-delete requires exact confirmation
`yes, delete`. Delete only paths the selected role entry owns; ambiguous or missing
ownership cancels deletion.

### Human view

Regenerate `.squad/roster.md` from canonical JSON. It is not authoritative and must say
so. Show active/inactive tables and links to provider artifacts that actually exist.

## Export verb

When the user asks to export, make portable, install to a project/user, use for this
session, or generate a plugin:

1. Read/canonicalize `.squad/roster.json` and read `.squad/goal.md`.
2. Ask or infer only missing export decisions: stable namespaced squad ID, destination,
   provider selection (Claude and Codex by default), and one selected runtime owner.
   Cadence comes from the goal and is not reinterpreted as destination.
3. Draft `.squad/manifest.json` schema v2 and show it before any write.
4. Run `squad-export plan` with explicit manifest, roster, target, and plan-file paths.
5. Print the complete writes/deletes and plan ID. Explain provider enforcement labels
   relevant to the chosen output.
6. Apply only after the user confirms that exact plan ID. Recompute from the same inputs;
   if anything changed, stop and plan again.
7. For `user`, require a second explicit global-write confirmation in addition to the
   plan ID. Never default to user scope.
8. Run `squad-export validate` after a filesystem apply and report checked artifacts.

### Destination rules

- `session`: no target and no discovery/global files; apply returns prompt-baked roles.
- `project`: target is the explicit selected Git repository root; writes stay inside it.
- `user`: target equals the explicit home; all artifacts are namespaced/receipted and
  apply additionally requires `--confirm-global-write`.
- `plugin`: target is an existing creator-selected non-home directory; generate both
  selected provider packages, activation instructions, canonical roles, runtime,
  license, and receipt, then stop before installation or enablement.

### Re-export, validate, uninstall

Re-export may update/delete only receipt-owned files whose current hashes still match.
Unowned collisions, modified owned files, traversal, symlink components, filesystem
roots, home misuse, and ambiguous paths fail safely.

`validate` checks receipts, hashes, modes, contracts, placeholders, and provider
artifacts. `uninstall` requires `--confirm` and removes only receipt-owned, unmodified
files. Preserve and report modified files. User uninstall also requires the explicit
home and global-write confirmation.

## Export exclusions

Never include `.squad/partner.md`, `.env*`, workspaces, worktrees, engagement/hand-off
records, secrets, caches, version-control state, or unrelated live/private data by
default. Exported packages are immutable vendored snapshots with no continuing runtime
dependency on the generator.

## Validation before roster writes

- `schema_version` is 2 for new writes.
- `execution_mode` equals `.squad/goal.md` and is one of `one-time`, `multi-use`,
  `evergreen`.
- IDs are unique lowercase kebab-case; purpose/description are non-empty.
- ownership includes at least one normalized project-relative path, no traversal.
- capabilities are non-empty portable identifiers.
- reasoning profile is `fast`, `balanced`, `deep`, or `inherit`; effort is `inherit`,
  `low`, `medium`, `high`, `xhigh`, or `max`.
- `active` is Boolean; environment/provider override shapes match schema.
- JSON is well formed and has no unknown fields.

If validation fails, do not write. Name the exact boundary failure.

## Refusals

- No goal or roster: route to `squad-onboard`.
- Collision or invalid contract: refuse until corrected.
- Hard-delete without exact confirmation: cancel.
- Direct `.squad/roster.md` edit: route to canonical JSON.
- Stale/mismatched plan: plan again.
- User export without global confirmation: refuse.
- Plugin generation request phrased as installation: generate only, then explain the
  separate activation step.

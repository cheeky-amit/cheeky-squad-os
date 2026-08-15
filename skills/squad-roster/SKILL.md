---
name: squad-roster
description: Use when the user wants to inspect, modify, audit, validate, or export the active squad, including showing the roster, removing a role, auditing scopes, exporting a project or user squad, building a Claude or Codex plugin, or uninstalling an exported squad. Owns the canonical provider-neutral .squad/roster.json, its human view, and the preview/confirm lifecycle for squad-export.
license: MIT
---

# squad-roster

You own `.squad/roster.json`, the source of truth for roles, and regenerate
`.squad/roster.md` after every roster write. Version 2 is provider-neutral. Legacy
Claude rosters remain readable through pure, deterministic in-memory migration.

You also expose **export** as a verb on this existing lifecycle skill. Export compiles
roles; it never authors a second roster and never installs or enables a plugin.

## Roster shape compatibility

Choose the source shape once: `schema_version: 2` means v2; no schema version means
legacy. Project roles into one read-only lifecycle view using these equivalents:

- identifier: v2 `id` // legacy `name`
- cadence: v2 `execution_mode` // legacy `mode`
- goal references: `squad_goal_ref` in both shapes; v2 `goal_ref` // legacy `role_goal`
- ownership: v2 `file_ownership.include` and `.exclude` // legacy `file_scope` and an
  empty exclude list
- provider data: v2 `provider_overrides`; legacy Claude data projected from `model`,
  `tools`, `agent_file`, and `isolation` (with no legacy Codex override)
- worktree isolation: v2 `provider_overrides.claude.isolation` // legacy `isolation`

The `//` notation names source-shape equivalents; it is not permission to fall back to
legacy aliases inside a malformed v2 object. Validate the selected shape and stop on a
missing required field. The projection is deterministic and read-only. Read-only
operations leave the source byte-for-byte untouched; ordinary mutations serialize the
same source shape. Convert legacy to v2 only as a separate operation that previews the
exact writes/deletes and requires the matching plan confirmation. If v2-only semantics
cannot be represented losslessly in legacy shape, stop and offer conversion instead of
dropping them.

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

An optional `environment` carries `workspace`, `directories`, non-secret `variables`,
`context`, and `tools`. Portable exports retain variable names but redact every value.
Provider overrides may tune Claude model/tools/legacy agent path or Codex
model/reasoning/sandbox. They do not replace purpose, description, or ownership.

## Legacy behavior

When the roster has no `schema_version: 2`, load it through the deterministic migration
path. Present the canonical in-memory result, but do not rewrite, relocate, or rename the
legacy roster or existing `.claude/agents/` files automatically.

Before any conversion write, preview the exact write/delete set and require the matching
confirmation. Declining leaves the existing squad byte-for-byte untouched.

For an ordinary mutation that stays legacy, reverse-project only fields legacy can
represent:

- canonical `id` → legacy `name`; `goal_ref` → `role_goal`
- `file_ownership.include` → `file_scope`; require `file_ownership.exclude` to be empty
- `provider_overrides.claude.model`, `.tools`, `.agent_file`, and `.isolation` → the
  same legacy top-level fields; any Codex override requires v2 conversion
- canonical environment `directories`/`variables` and context `source`/`target` → legacy
  `dirs`/`env` and `from`/`into`; never serialize secret values

After reverse projection, project the proposed legacy object forward again and compare
identifier, goal reference, include/exclude ownership, Claude provider choices, and
isolation. If any lifecycle meaning changes, refuse the mutation and offer a separately
previewed v2 conversion. Never mix v2 keys into a schema-less legacy object.

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
3. **Refuse the 5-seat cap (hard rule #16).** Count active roles (`active: true`); if the new role would make the count 6, refuse the write — same message shape as the ID-collision refusal: name the current active roster and point at consolidating two roles or deactivating one first. Deactivated roles never count. This is the last line of defense — `squad-onboard`'s decomposition cap and `squad-role`'s preflight should have already caught this, but a direct roster write bypasses both.
4. Validate required neutral fields, optional provider overrides, and — v2 only — each `onboarded_skills` entry (`name`, `kind` (`knowledge` | `execution`), `local_path`, `purpose`, `approval_mode` required; `source_url`, `approved_at` optional; `additionalProperties: false`). **Provenance & limits enforcement:** for every `onboarded_skills` entry, read the file at `local_path` and refuse the write if it does not contain a `## Provenance & limits` heading — same failure shape as an ID collision or a missing required field. An onboarded skill without that block is not onboarded (see `squad-role`'s Q8), and this is the last line of defense for that contract, the same role this step already plays for the 5-seat cap.
5. For a v2 roster, append the role and pretty-print v2 JSON. For a legacy roster, preserve
   its legacy shape using the reverse projection above. If the new role has exclusions,
   Codex overrides, `onboarded_skills`, or any other v2-only semantics that fail the
   forward-projection check, stop and offer a separate conversion plan; do not add a
   partially represented role. Regenerate `.squad/roster.md` only after the selected-shape
   write succeeds.
6. Report every generated provider artifact separately from the neutral roster write.

### Deactivate or remove

**Before asking for confirmation, state the blast radius.** One line: what this removal
orphans — the role's `file_ownership`/`file_scope` paths (deliverables that will have no
owner), any hand-off manifests addressed to or from this role
(`.squad/role-comm-<role>--*`), and its onboarded skills, if any (the manifest entry
goes with the role; the files under `.squad/skills/<role-id>/**` are left on disk,
unreferenced). Then ask whether to soft-deactivate (`active: false`) or hard-delete the
roster entry and referenced generated role/goal artifacts. Hard-delete requires exact
confirmation `yes, delete`. Delete only paths the selected role entry owns; ambiguous or
missing ownership cancels deletion.

### Refresh skills

Re-runs a role's Q8 research against its **existing** onboarded set — an audit-and-upgrade pass, not a fresh onboarding. Worth running: on every iteration of an Evergreen or Multi-use squad's natural cadence (a long-running squad's context goes stale faster than a one-time squad's), and any time a role's `## Declared capability gaps` (see `squad-role`'s execution-gap check) might have closed — a newly connected MCP server or installed CLI can unlock an execution skill that didn't exist at intake.

1. For the named role (or every active role, if asked for the whole squad), re-run Q8's two-dimension research (knowledge + execution) against the role's current purpose and file scope — same curated source list, same research-first rule, same per-dimension "state plainly when nothing turns up."
2. **Diff** the new research against each existing `onboarded_skills` entry and against the role's `## Declared capability gaps`:
   - **Better source found** — a newer or more authoritative source for the same capability.
   - **Source updated** — the same source URL, materially changed content since `approved_at`.
   - **Limit resolved** — a `## Provenance & limits` "Known limits" line no longer applies.
   - **Gap closed** — a declared capability gap now has a candidate execution skill where none existed before.
3. **Propose upgrades** through the exact same approval gate Q8 uses (default `approval_mode: user`; auto-approve only through the same two channels — a `.squad/partner.md` standing constraint, or `.squad/goal.md`'s `skill_onboarding: auto`). Nothing upgrades silently, regardless of how the original entry was approved.
4. On approval: update the `onboarded_skills` entry (new `source_url`, `local_path` if the file moved), rewrite the local SKILL.md file (its `## Provenance & limits` block gets a fresh `Intake date` and `Sources searched`), and bump `approved_at` to the refresh's timestamp. Regenerate `roster.md`. If a declared gap closed, remove the corresponding bullet from the role's `## Declared capability gaps` and note the resolution.
5. Report what changed, role by role — upgraded / unchanged / gap-closed — never silent when nothing changed either (e.g. *"`compliance-checker`: research found nothing newer — 2 skills unchanged."*).

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
artifacts. `uninstall` first prints or saves the complete removal plan, then applies only
with the matching `--plan-file` and `--confirm-plan-id`. It removes only receipt-owned,
unmodified files. Preserve and report modified files. User uninstall also requires the
explicit home and global-write confirmation on apply.

## Export exclusions

Never include `.squad/partner.md`, `.env*`, workspaces, worktrees, engagement/hand-off
records, secrets, caches, version-control state, or unrelated live/private data by
default. Exported packages are immutable vendored snapshots with no continuing runtime
dependency on the generator.

**Onboarded-skill manifests export; payloads don't (yet).** A role's `onboarded_skills`
entries — name, source, local path, purpose, approval mode/timestamp — are part of the
roster contract and travel with every export, the same as any other role field. The
skill files themselves, under `.squad/skills/**`, are not vendored into the snapshot: an
exported squad's `local_path` references point at bytes the export doesn't carry. This
is a documented limitation, not an oversight — see `CHANGELOG.md`'s 1.2.0 entry and the
follow-up in `docs/ROADMAP.md`.

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
- each `onboarded_skills` entry has `name`, `kind` (`knowledge` | `execution`),
  `local_path`, `purpose`, `approval_mode`; `source_url`/`approved_at` are optional; no
  unknown fields; the file at `local_path` contains a `## Provenance & limits` heading.
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

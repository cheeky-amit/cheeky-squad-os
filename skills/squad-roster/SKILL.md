---
name: squad-roster
description: Use when the user wants to inspect, modify, or audit the active squad — phrases like "show the roster", "who's on the squad", "list teammates", "remove <role>", "deactivate <role>", "what does <role> own", "audit scopes", "show file scopes", "what's <role>'s goal". Manages .squad/roster.json as the source of truth and auto-generates .squad/roster.md as a human-readable view. Also called by squad-role to register newly generated roles and by the PermissionRequest hook to look up scopes.
version: 0.1.0
author: cheeky-squad-os
license: MIT
compatible-with: [claude-code, agentskills-1.0]
---

# squad-roster

You manage `.squad/roster.json` — the source of truth for who's on the squad — and regenerate `.squad/roster.md` (human-readable view) on every write.

## File schema

`.squad/roster.json`:

```json
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "one-time | multi-use | evergreen",
  "created": "<ISO-8601>",
  "roles": [
    {
      "name": "klaviyo-data-puller",
      "purpose": "Pull Klaviyo flow performance via MCP and dump as JSON",
      "agent_file": ".claude/agents/klaviyo-data-puller.md",
      "role_goal": ".squad/role-goal-klaviyo-data-puller.md",
      "file_scope": ["reports/klaviyo/**", "data/klaviyo/**"],
      "tools": ["Read", "Write", "Bash", "mcp__claude_ai_Klaviyo__*"],
      "model": "sonnet",
      "active": true,
      "created": "<ISO-8601>"
    }
  ]
}
```

`.squad/roster.md` is regenerated from `roster.json` after every write. It is **not authoritative** — never read from it. Always read from the JSON.

**Source of truth for `mode`:** `.squad/goal.md` frontmatter is authoritative (it is what `squad-spawn` reads). The `mode` in `roster.json` is a **mirror** kept for the human view. On every write, re-derive it from `.squad/goal.md` and overwrite the roster copy; if they diverged, print a warning naming both values. Never let a user edit drive `roster.json`'s mode independently of the goal.

## Operations

### List / show

If the user asks "show the roster", "who's on the squad", or similar:

1. Read `.squad/roster.json`. If absent: print *"No roster. Run `/cheeky-squad-os:squad-onboard` to start a squad."* and stop.
2. Print a tabular view of all roles: name, purpose (truncated), model, active flag, file_scope (truncated).
3. Print the squad mode and creation date as a one-line summary.

### Detail (one role)

If the user asks "what does `<name>` own", "show `<name>`", or similar:

1. Find the role in `.squad/roster.json`.
2. Read `.claude/agents/<name>.md` and `.squad/role-goal-<name>.md`.
3. Print: name, purpose, full file_scope (one per line), tools, model, agent_file path, role_goal path, active flag, created date. Then print the role goal contents.

### Add (called by squad-role)

When `squad-role` finishes generating a new role, it calls into this skill to register the entry. Steps:

1. Read `.squad/roster.json` (or create it with the schema above if absent).
2. Check for name collision — refuse if `roles[].name` already contains the proposed name.
3. Validate all required fields are present (name, purpose, agent_file, role_goal, file_scope, tools, model).
4. Append the new role to `roles`.
5. Write `.squad/roster.json` (pretty-printed, 2-space indent).
6. Regenerate `.squad/roster.md` (see "Regenerate human view" below).
7. Print confirmation: *"Role `<name>` added to roster."*

### Deactivate / remove

If the user asks "remove `<name>`" or "deactivate `<name>`":

1. Find the role.
2. Ask: *"Soft-deactivate (`active: false`, file kept) or hard-delete (remove entry, file deleted)?"*
3. **Soft-deactivate:** flip `active: false` in roster.json. Role file and role goal file are kept on disk. `squad-spawn` will skip inactive roles. Reversible — user can flip it back.
4. **Hard-delete:** ask once more for confirmation (*"This deletes `.claude/agents/<name>.md` and `.squad/role-goal-<name>.md`. Confirm with `yes, delete`."*). On exact-match confirmation: remove from `roles`, delete the two files, write roster.json, regenerate roster.md.
5. If neither: leave unchanged.

### Audit scopes

If the user asks "audit scopes", "show file scopes", or similar:

1. Read all roles' `file_scope` arrays.
2. Print a table: scope glob → role name.
3. Highlight overlaps — if two roles claim the same path, print a warning. In Multi-use mode, overlaps cause merge conflicts; in One-time mode, they may produce inconsistent writes.

### Regenerate human view

After any write to `.squad/roster.json`, regenerate `.squad/roster.md` with this structure:

```markdown
# Squad roster

**Goal:** [.squad/goal.md](goal.md)
**Mode:** <mode>
**Created:** <created>

## Active roles

| Name | Purpose | Model | File scope |
| --- | --- | --- | --- |
| <name> | <purpose, truncated to 60 chars> | <model> | <scope[0]>, <scope[1]>, … |

## Inactive roles

(only shown if any roles have `active: false`)

| Name | Purpose | Model |
| --- | --- | --- |

## Files

| Role | Definition | Role goal |
| --- | --- | --- |
| <name> | [.claude/agents/<name>.md](../.claude/agents/<name>.md) | [.squad/role-goal-<name>.md](role-goal-<name>.md) |

---

*Auto-generated from `roster.json` by `squad-roster`. Edit `roster.json`, not this file.*
```

## Validation before write

Before writing `.squad/roster.json`:

- `mode` equals `.squad/goal.md`'s mode — re-derive it from goal.md and overwrite the roster copy (goal.md is authoritative); warn if they had diverged. It must be one of `one-time`, `multi-use`, `evergreen`.
- Every role has `name` (kebab-case, no collisions), `purpose` (non-empty), `agent_file` (path exists or will exist), `role_goal` (path exists or will exist), `file_scope` (non-empty array of strings), `tools` (non-empty array), `model` (`sonnet`, `opus`, `haiku`, or `inherit`).
- `active` is a boolean.
- JSON is well-formed.

If validation fails, do not write. Print the specific failure and ask the user to fix.

## Refusals

- **No goal:** refuse, point at `squad-onboard`.
- **Add with collision:** refuse, ask for a different name.
- **Hard-delete without exact confirmation phrase:** treat as cancel.
- **Edit `.squad/roster.md` directly:** explain it's auto-generated; route the edit to `roster.json`.

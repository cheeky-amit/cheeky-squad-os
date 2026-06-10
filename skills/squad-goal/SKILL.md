---
name: squad-goal
description: Use when the user wants to set, change, view, or replace the squad's north-star goal, or manage multiple squads in one project — phrases like "set the squad goal", "change the goal", "what's our goal", "show the goal", "update the goal", "the goal is wrong", "we've shifted direction", "park this squad", "switch squads", "list squads", "bring back the <name> squad". Manages .squad/goal.md as the binding north-star constraint that every other skill and hook reads from, and .squad/squads/<name>/ as parked squads. This skill is read-write on goal/squad lifecycle files only; it does not generate roles or spawn workers.
version: 0.1.0
author: cheeky-squad-os
license: MIT
compatible-with: [claude-code, agentskills-1.0]
---

# squad-goal

You manage `.squad/goal.md` — the squad's binding north-star outcome. Every other skill in cheeky-squad-os reads this file; the `SessionStart` hook injects its contents into every session's context.

Run the operation the user asked for. Operations are: **read**, **write**, **replace**, **show diff**, **park**, **switch**, **list squads**, **refuse**.

## File schema

Goals are saved at `.squad/goal.md` with this exact structure:

```markdown
---
mode: one-time | multi-use | evergreen
created: <ISO-8601 datetime>
target: <ISO-8601 deadline or "ongoing">
---

# Squad goal

<one outcome-framed paragraph — measurable, time-bounded>

## Definition of done

- <observable signal 1>
- <observable signal 2>
- <observable signal 3>

## Out of scope

- <explicit exclusion 1>
- <explicit exclusion 2>
```

The frontmatter is required. `target` is `"ongoing"` for evergreen mode and an ISO-8601 date otherwise.

## Operations

### Read / show

If the user asks "what's our goal", "show the goal", or similar:

1. Read `.squad/goal.md`.
2. If it exists: print the full contents, then the mode, created date, and target deadline on a single summary line.
3. If it doesn't exist: print *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` to set one."* and stop.

### Write (first time)

This path is normally invoked by `squad-onboard` at the end of its flow, with a pre-confirmed outcome from the user.

1. Confirm `.squad/goal.md` does not exist. If it does, route to **replace** instead.
2. Create `.squad/` if needed (`mkdir -p`).
3. Compose the file with the schema above, using:
   - `mode`: inferred or user-overridden from onboarding
   - `created`: current UTC time in ISO-8601
   - `target`: deadline from the outcome statement, or `"ongoing"` for evergreen
   - Body: the user-confirmed outcome paragraph
   - Definition of done: 3–5 observable signals derived from the outcome
   - Out of scope: anything the user explicitly excluded
4. Write the file.
5. Print: *"Squad goal saved to `.squad/goal.md`. The SessionStart hook will inject it into every new session."*

### Replace

If `.squad/goal.md` already exists and the user wants to change it:

1. Read the existing goal.
2. Show it side-by-side with the proposed new goal.
3. Ask: *"This replaces the current goal. Existing roles in `.squad/roster.json` were generated against the old goal — they may no longer fit. Replace anyway? (If the old initiative isn't finished, I can **park** the current squad instead and start this as a new one — nothing is lost.)"*
4. If yes: write the new goal. Then check `.squad/roster.json` — if any roles exist, print a warning: *"Roster has [N] roles. Run `/cheeky-squad-os:squad-roster` to review them against the new goal; some may need replacing."*
5. If no: leave the file unchanged.

### Show diff

If the user is mid-edit and asks "show me what I'm changing":

1. Read current `.squad/goal.md`.
2. Show their proposed text alongside.
3. Highlight the differences in plain language (mode change, deadline change, definition of done changes, scope changes).

## Multiple squads: park / switch / list

One project runs **one active squad** — `.squad/goal.md` + `.squad/roster.json` are what every hook, script, and skill reads, and concurrent squads would collide on `.claude/agents/` names and hook lookups. A second initiative doesn't replace the first, though: it parks it.

**Layout:** parked squads live at `.squad/squads/<slug>/` (slug: short kebab-case name — derive from the goal, confirm with the user). Each holds the squad's durable state: `goal.md`, `roster.json`, `roster.md`, `role-goal-*.md`, `verification.md` (if present), and `agents/` (the role definition files, moved out of `.claude/agents/` so parked roles can't auto-delegate or collide with the active squad's names). Ephemeral state is **not** parked: `.squad/role-comm-*` manifests are deleted (per-engagement), `.squad/workspaces/<role>/` and `.claude/worktrees/<role>/` are left to be re-provisioned/re-created on resume. Parked dirs follow the same commit policy as active state — everything in them is commit-grade.

### Park

1. Confirm no dispatch is mid-flight (workers running, or worktrees with uncommitted changes the user hasn't dealt with). If in doubt, ask — never park under a running squad.
2. Pick the slug with the user. Refuse if `.squad/squads/<slug>/` already exists.
3. Move `goal.md`, `roster.json`, `roster.md`, all `role-goal-*.md`, and `verification.md` from `.squad/` into `.squad/squads/<slug>/`.
4. For each role in the parked roster, move its `agent_file` from `.claude/agents/` into `.squad/squads/<slug>/agents/`.
5. Delete any `.squad/role-comm-*.md`.
6. Report: *"Squad `<slug>` parked. No active squad — run `squad-onboard` for a new one, or `switch` to a parked squad."*

### Switch

1. List parked squads (below); confirm the target.
2. If a squad is currently active, **park it first** (full Park flow — needs its own slug).
3. Restore the target: move its files from `.squad/squads/<slug>/` back to `.squad/`, and its `agents/*.md` back to `.claude/agents/`. If an agent filename already exists in `.claude/agents/` (a non-squad subagent), stop and surface the collision — never overwrite.
4. Report the restored goal (one-line summary) and remind: workspaces/worktrees are not restored — `squad-spawn` re-provisions environments on next dispatch.

### List squads

Print the active squad (from `.squad/goal.md` frontmatter + first goal line) and every parked squad under `.squad/squads/*/` (slug, mode, target, first goal line from each `goal.md`). If a parked dir is missing `goal.md` or `roster.json`, flag it as damaged rather than offering to switch to it.

## Refusals

Refuse and explain when:

- **Delete request:** Never delete `.squad/goal.md` without explicit confirmation. If user says "delete the goal", ask *"This unsets the squad's north-star. Confirm with `yes, delete`."* and only proceed on that exact phrase.
- **Ask, not outcome:** If the user proposes a new goal that's an ask ("make X better") not an outcome (measurable + time-bounded), push back once: *"Goals must be outcomes. What's the measurable signal, and by when?"* Then accept whatever they say next.
- **No mode:** If the user is writing a goal but the mode is unclear, infer from the goal shape (see `squad-onboard` for the inference table) and state your inference. Don't ask the user — let them override if they disagree.

## Validation before write

Before writing, sanity-check:

- The body paragraph contains at least one number or measurable phrase (revenue, conversion, time bound, count, percentage).
- `target` parses as a valid ISO-8601 date or is the literal string `"ongoing"`.
- Definition of done has at least one bullet.
- Frontmatter is valid YAML.

If any check fails, fix it interactively with the user — don't write a broken file.

## What this skill does NOT do

- Does not generate roles (that's `squad-role`).
- Does not spawn workers (that's `squad-spawn`).
- Does not modify `.squad/roster.json` (that's `squad-roster`).
- Does not run the onboarding flow (that's `squad-onboard`).

If the user asks for any of those, hand off to the appropriate skill.

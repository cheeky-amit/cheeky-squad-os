---
name: squad-spawn
description: Use when the user wants to dispatch the squad to actually do the work — phrases like "dispatch the squad", "spawn the team", "start the work", "run it", "go", "kick off", "let's do it", or any "ready to start" signal after onboarding and role generation. Branches on the squad's mode — One-time spawns subagents, Multi-use spawns Agent Teams teammates (with --worktree per teammate), Evergreen surfaces scheduling options for the user to choose. Bakes the full text of .squad/goal.md and the relevant .squad/role-goal-<role>.md into every spawn prompt — that is the only reliable context channel from parent to worker.
version: 0.1.0
author: cheeky-squad-os
license: MIT
allowed-tools: [Read, Bash, Agent]
compatible-with: [claude-code, agentskills-1.0]
---

# squad-spawn

You orchestrate dispatch. The squad has been onboarded (`.squad/goal.md` exists), roles have been generated (`.squad/roster.json` is populated, `.claude/agents/<role>.md` files exist). Your job is to launch them in the right way for the squad's mode.

## Preflight — refuse if not ready

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."* and stop.
2. Read `.squad/roster.json`. If absent or `roles` array is empty: refuse with *"Roster is empty. Run `/cheeky-squad-os:squad-role` to generate at least one role."* and stop.
3. For each role in roster: verify `.claude/agents/<role.name>.md` and `.squad/role-goal-<role.name>.md` exist. If any missing: print the gaps and ask the user to re-run `squad-role` for the missing ones.
4. Read each `.squad/role-goal-<role.name>.md`.
5. Note the squad's mode from `goal.md` frontmatter.

## Build the spawn prompt (per role)

Every spawn — subagent, teammate, scheduled — receives the same prompt structure:

```
You are the <role.name> teammate on a cheeky-squad-os squad.

# Squad goal (binding north-star)
<full contents of .squad/goal.md>

# Your role's goal
<full contents of .squad/role-goal-<role.name>.md>

# Your role's file scope
<role.file_scope from roster.json>

# Your task on this invocation
<task description — see below per mode>

Read .squad/goal.md and .squad/role-goal-<role.name>.md at any time during your work. Stay inside your file scope. Hand off deliverables by writing to your scope.
```

**Hard rule #4:** the full text of `.squad/goal.md` and the role's `.squad/role-goal-<role.name>.md` is the only reliable channel from parent to subagent. The SessionStart hook does not fire for subagents. Bake the goal text in; don't rely on hook injection for the One-time path.

## Branch on mode

### Mode: One-time

For each role in `.squad/roster.json` (filter `active: true`):

1. Build the spawn prompt using the template above. For "your task on this invocation", derive from the role's purpose plus the squad's definition of done — what does this role contribute *this run*?
2. Invoke the `Agent` tool. Pass:
   - `description`: the role's purpose (3–5 words)
   - `subagent_type`: the role's name (matches `.claude/agents/<role.name>.md`)
   - `prompt`: the composed spawn prompt
3. If the role's frontmatter has `isolation: worktree`, the subagent automatically runs in a worktree (per sub-agents doc; the frontmatter handles it — no extra flag needed from you).
4. Subagents can run in parallel if their workstreams are independent. Send multiple `Agent` tool calls in one message to dispatch in parallel. Otherwise dispatch sequentially.
5. Wait for each subagent's deliverable summary. Synthesize results into a user-facing report.

**This direct-`Agent` path is the default** and is the right choice for small squads (≤3 roles).

#### Optional: dispatch as a dynamic Workflow (larger / cross-checked squads)

For a **larger One-time squad** (4+ active roles), or when you want deterministic fan-out, structured per-role hand-offs, and in-session resume, the dispatch can run as a dynamic **Workflow** instead of hand-issued `Agent` calls.

You (a skill) **cannot launch a workflow yourself** — the only triggers are the literal keyword `workflow` in a user prompt, `/effort ultracode`, a bundled command, or a saved `/<name>` command, and every run needs the user's approval. So do **not** try to invoke it. Instead, point the user at the dedicated command:

> *"This squad has N roles — it's a good fit for the Workflow dispatch path: deterministic fan-out, structured hand-offs, resumable in-session. Run `/cheeky-squad-os:squad-workflow` to dispatch it that way (you'll be asked to approve the workflow run). Note: workflow subagents run with file edits auto-approved, which bypasses the file-scope hook — so that path fans out read/analyze roles with scoped writes; keep code-mutating roles on this direct path."*

Then stop, or proceed with the direct-`Agent` path if the user prefers it. See the ["Dynamic Workflows"](../../ARCHITECTURE.md) section of `ARCHITECTURE.md` for where this fits and the canonical script shape in `templates/squad-dispatch.workflow.js`.

### Mode: Multi-use

1. **Check Agent Teams.** Read `$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from environment (use Bash: `echo "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"`).
2. **If set to `1`:**
   - **(Optional) pre-create worktrees.** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/spawn.sh` with the roster path and goal path. This *only* pre-creates one git worktree per active role under `.claude/worktrees/<role>/` (branch `squad-<role>`) and emits one JSON line per worktree. It launches **no** Claude session and bakes **no** prompt — it is a working-directory convenience, not the teammate launcher.
   - **Spawn the teammates.** As the team lead, create the Agent Team and spawn one teammate per active role, referencing each role's definition at `.claude/agents/<role>.md` **by name** (the documented Agent Teams mechanism — teammates are spawned by the lead in natural language, not by a CLI flag). Pass each teammate the spawn prompt built from the template above as its initial instructions. There is no `--worktree <role>` teammate-launch flag; do not assert one.
   - **File isolation** between teammates is enforced by **disjoint `file_scope`** per role (agent-teams doc: "two teammates editing the same file leads to overwrites — break the work so each teammate owns a different set of files"). The roster's per-role `file_scope` is that vehicle. If you want a teammate to work inside its pre-created worktree, point it there explicitly using the path from `spawn.sh`'s JSON; nothing wires that automatically.
   - Per agent-teams doc: when a subagent definition is used as a teammate, `skills` and `mcpServers` frontmatter do **not** propagate; `tools` and `model` do; the body is appended to the teammate's system prompt.
   - Print the teammate names back to the user. They can address any teammate by name in subsequent turns.
3. **If unset, `0`, or anything else:**
   - Print a one-paragraph explanation of what Agent Teams adds: shared task list, mailbox, direct teammate-to-teammate messaging, true parallel execution.
   - Offer to write `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` to `~/.claude/settings.json`. **Ask consent in the same turn.** Never write the setting silently. Format the proposed change so the user sees the exact JSON before accepting.
   - If user accepts: write the setting (merge with existing JSON, don't clobber). Tell them to restart Claude Code. Stop — they'll resume `squad-spawn` after restart.
   - If user declines: fall back to **One-time mode dispatch** (sequential subagents). Print a warning: *"Falling back to subagents — mailbox, shared task list, and direct teammate-to-teammate messaging are unavailable. File isolation now comes from each subagent honoring its `file_scope`, plus per-subagent worktrees where a role sets `isolation: worktree` in its frontmatter."*

### Mode: Evergreen

The plugin cannot create durable scheduled work on the user's behalf. Surface three options and print exact instructions for each. Ask the user to pick one before proceeding.

**Option A — `/loop` (in-session, 7-day max):**

The recurring task lives in the current session, fires at the chosen interval, and auto-expires 7 days after creation (per scheduled-tasks doc). Requires the session to be open.

Print this for the user to copy:

```
/loop <interval> <prompt>
```

Where `<interval>` is e.g. `1w` for weekly, `1d` for daily, `1h` for hourly. The `<prompt>` is the dispatch directive for the squad — something like `dispatch the cheeky-squad-os squad against the current goal`.

**Option B — Cloud Routine (durable, Anthropic-managed):**

The user creates this themselves via the Claude Code routines surface. The plugin does not call any scheduling tool on their behalf. Print:

```
To set up a cloud routine for this squad:
  1. Note your squad goal location: <absolute path to .squad/goal.md>
  2. Open your Claude Code routines surface (CLI or dashboard, depending on your version)
  3. Create a routine with:
     - Schedule: <user's chosen cron expression>
     - Prompt: "dispatch the cheeky-squad-os squad against .squad/goal.md"
     - Repository: this project's git remote (so the routine clones and reads .squad/)
```

**Option C — Desktop scheduled task (durable, local):**

```
To set up a desktop scheduled task:
  1. Open the Claude Code desktop app
  2. Create a new scheduled task with:
     - Schedule: <user's chosen cron expression>
     - Working directory: <absolute path to this project>
     - Initial prompt: "dispatch the cheeky-squad-os squad against the current goal"
```

After the user picks an option, confirm: *"Squad is set up for Evergreen mode via [option]. The next run will invoke the squad against the current `.squad/goal.md`."*

## Per-spawn synthesis

For One-time and Multi-use modes, after the squad finishes (or per-iteration in Evergreen):

1. Read each role's outputs from their `file_scope`.
2. Compose a user-facing summary: what each role produced, where the artifacts live, what's next.
3. Surface any role that failed or returned an error.
4. Suggest follow-up actions (replace a role, change a scope, replace the goal).

## Refusals

- No goal → refuse, point at `squad-onboard`.
- Empty roster → refuse, point at `squad-role`.
- Missing role files → refuse, list the gaps.
- Multi-use mode with Agent Teams env unset and user declines to enable → fall back to subagents (do not refuse).
- Evergreen mode without the user picking a scheduling option → wait; do not silently default.

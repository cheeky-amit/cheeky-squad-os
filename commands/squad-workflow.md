---
description: Dispatch a One-time squad as a dynamic Workflow — deterministic fan-out over roles, structured hand-offs, in-session resume.
argument-hint: "[--force] [--save]"
---

# squad-workflow

Run a dynamic **workflow** that dispatches the current cheeky-squad-os squad: one
agent per active role, fanned out deterministically, each returning a structured
result, then synthesized into one report.

> Mentioning "workflow" here is deliberate — it is one of the only ways to invoke
> the Workflow runtime. A skill cannot launch a workflow on your behalf; this
> command is the user-triggered entry point. You will be asked to approve the run.

Arguments: `$ARGUMENTS` — `--force` to use the workflow path even for small (≤3 role)
squads; `--save` to keep the generated script under `.claude/workflows/`.

## Your task

1. **Preflight (refuse if not ready).**
   - Read `.squad/goal.md`. If absent → stop: *"No squad goal. Run `/cheeky-squad-os:squad-onboard` first."*
   - Read `.squad/roster.json`. If absent or no `active: true` roles → stop: *"No active roles. Run `/cheeky-squad-os:squad-role`."*
   - Confirm the goal's `mode` is **one-time**. Workflows map to One-time only. If `multi-use` → point at `/cheeky-squad-os:squad-spawn` (Agent Teams; workflows forbid the mid-run messaging Multi-use needs). If `evergreen` → point at the scheduling options in `squad-spawn` (a workflow is not a scheduler).

2. **Availability gate.** Dynamic Workflows are a research-preview feature (recent Claude Code, paid plans) and can be org-disabled (`disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS`). If you cannot run a workflow in this environment, **fall back gracefully**: tell the user, and run the standard One-time dispatch from `/cheeky-squad-os:squad-spawn` (direct `Agent` calls) instead. Do not hard-fail.

3. **Size check.** If the squad has ≤3 active roles and `--force` was not passed, say the direct-`Agent` path in `squad-spawn` is simpler and recommend it — a workflow earns its overhead at 4+ roles or when adversarial cross-checking adds value. Proceed only if the user wants it anyway.

4. **Safety briefing (state this before running).** The subagents a workflow spawns always run in **acceptEdits** — their file edits are auto-approved, which **bypasses the squad's `PermissionRequest` file-scope hook**. So this command dispatches **read/analyze** roles whose writes are confined to their own `file_scope` by instruction (baked into each agent prompt), not by the hook. Any role that must mutate shared code should stay on the hook-gated `squad-spawn` path, or be run as its own write-stage workflow with a sign-off gate. Confirm the user is OK with this posture (or to exclude write-roles).

5. **Build the workflow inputs (hard rule #4 — bake everything in).** Workflow scripts have no filesystem access, so assemble an `args` object from the live files:
   - `goal`: full text of `.squad/goal.md`.
   - `roles`: for each `active: true` role in `roster.json` (excluding any write-roles the user chose to hold back) → `{ name, roleGoal: <full text of .squad/role-goal-<name>.md>, fileScope: <roster file_scope>, task: <this-run contribution derived from the role purpose + the goal's definition of done>, model: <roster model or omit> }`.

6. **Author and run the workflow.** Follow the shape in `${CLAUDE_PLUGIN_ROOT}/templates/squad-dispatch.workflow.js` (read it). Author the script (or pass that template's logic) and run it via the Workflow tool with the `args` you built. The script fans out one `agent()` per role with `agentType` = the role name (so `.claude/agents/<name>.md` loads), each returning the `{role, summary, artifacts, status, follow_ups}` contract, then returns a structured digest.

7. **(Optional) persist.** If `--save` was passed, write the concrete script to `.claude/workflows/squad-dispatch.js` so it is committed and rerunnable (regenerate it whenever the roster changes — a saved script reflects the roster at generation time, not run time).

8. **Synthesize.** From the workflow's returned digest, read each role's artifacts from its `file_scope` and compose a user-facing report: what each role produced, where the artifacts live, what's `done` / `partial` / `blocked`, and the collected `follow_ups`. Surface any blocked role prominently.

## Notes

- This command does **not** replace `/cheeky-squad-os:squad-spawn`. It is an optional, opt-in dispatch backend for One-time squads. `squad-spawn` remains the default and the only path for Multi-use and Evergreen.
- Resume is **in-session only** — if Claude Code exits mid-run, the next session starts the workflow fresh.

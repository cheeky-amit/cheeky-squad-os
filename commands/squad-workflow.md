---
description: Dispatch a One-time squad as a dynamic Workflow — deterministic fan-out over roles, structured hand-offs, in-session resume.
argument-hint: "[--force] [--save] [--chain]"
---

# squad-workflow

Run a dynamic **workflow** that dispatches the current cheeky-squad-os squad: one
agent per active role, fanned out deterministically, each returning a structured
result, then synthesized into one report.

> Mentioning "workflow" here is deliberate — it is one of the only ways to invoke
> the Workflow runtime. A skill cannot launch a workflow on your behalf; this
> command is the user-triggered entry point. You will be asked to approve the run.

Arguments: `$ARGUMENTS` — `--force` to use the workflow path even for small (≤3 role)
squads; `--save` to keep the generated script under `.claude/workflows/`; `--chain`
to keep existing hand-off manifests (this run consumes a previous stage's output —
e.g. a write-stage run after a read-stage run) instead of clearing them.

## Your task

1. **Preflight (refuse if not ready).**
   - Read `.squad/goal.md`. If absent → stop: *"No squad goal. Run `/cheeky-squad-os:squad-onboard` first."*
   - Read `.squad/roster.json`. If absent or no `active: true` roles → stop: *"No active roles. Run `/cheeky-squad-os:squad-role`."*
   - Confirm the goal's `mode` is **one-time**. Workflows map to One-time only. If `multi-use` → point at `/cheeky-squad-os:squad-spawn` (Agent Teams; workflows forbid the mid-run messaging Multi-use needs). If `evergreen` → point at the scheduling options in `squad-spawn` (a workflow is not a scheduler).

2. **Availability gate.** Dynamic Workflows need Claude Code v2.1.154+ and are available on all paid plans, with Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry (on Pro, turned on from the Dynamic workflows row in `/config`); they can also be org-disabled (`disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS`). If you cannot run a workflow in this environment, **fall back gracefully**: tell the user, and run the standard One-time dispatch from `/cheeky-squad-os:squad-spawn` (direct `Agent` calls) instead. Do not hard-fail.

3. **Size check.** If the squad has ≤3 active roles and `--force` was not passed, say the direct-`Agent` path in `squad-spawn` is simpler and recommend it — a workflow earns its overhead at 4+ roles or when adversarial cross-checking adds value. Proceed only if the user wants it anyway.

4. **Safety briefing (state this before running).** The subagents a workflow spawns always run in **acceptEdits** and inherit your tool allowlist, regardless of your session's mode — file edits are auto-approved. The practical effect: a role's writes are **not gated by its `file_scope`** on this path. Whether that's because the squad's `PermissionRequest` file-scope hook never fires for workflow subagents, or fires and its result is simply overridden by `acceptEdits`, is **not established** — don't assume either. What's certain is the effect, so **don't rely on file-scope enforcement here**. Accordingly, this command dispatches **read/analyze** roles whose writes are confined to their own `file_scope` by instruction (baked into each agent prompt), not by the hook. Any role that must mutate shared code should stay on the hook-gated `squad-spawn` path, or be run as its own write-stage workflow with a sign-off gate. Confirm the user is OK with this posture (or to exclude write-roles).

5. **Hand-off channel hygiene (staleness).** Manifests under `.squad/role-comm-*.md` are per-engagement working state. Without `--chain`: delete any leftover manifests before dispatching — they are from a completed prior run, and baking them would feed roles stale hand-offs (the deliverables they referenced live on in committed `file_scope` paths; only the routing note is discarded). With `--chain`: keep them — this run is a follow-on stage and those manifests are its legitimate input.

   **Engagement records, same rule, narrower target (hard rule #11).** `spawnPrompt()` bakes Step 0 into every role's prompt, so each role dispatched here publishes `.squad/role-plan-<role>.md`. Without `--chain`: delete that file for each role **this run dispatches**, and only those — never a role you held back in step 4, and never a role running on another path. With `--chain`: keep them; the record still describes the still-current engagement, and the role appends to `## Amendments` rather than starting over. Be honest with the user about the limit: on this path Step 0 is *asked*, not enforced — under `acceptEdits` the hook's plan gate is inert (step 4), so a role that skips it still writes its files, it just leaves no reasoning behind for `squad-verify`'s `## Process` table.

   **The escalation contract, same honesty (hard rules #14–#15).** `spawnPrompt()` also bakes the escalation contract: if one of a role's `stop:` bounds fires (its role goal's `## Stop conditions`, prompt-baked as part of `role.roleGoal`), the role writes `.squad/role-plan-<role>.md` with `status: escalated`, `fired:` set to the bullet verbatim, and the three hand-back sections — exactly as on the direct-`Agent` path — **and** sets `status: "blocked"` on its returned structured result, so the two agree. The pairing matters because they're read by different consumers at different times: the digest's `status: "blocked"` is what this run's synthesis surfaces to the user immediately (step 9), while the engagement record is what `squad-verify` and every later re-verify actually trust — a `"blocked"` result with no matching `status: escalated` record is process evidence of a skipped Step 0, not an open escalation. Same limit as Step 0 above: nothing on this path mechanically stops a role from finishing quietly instead of escalating, or from returning `"done"` with a bound it should have honored still live. There is no `resolved` status or `resolution:` field anywhere a role writes, on any path — the human's ruling on an escalation lands only in `.squad/verification.md`, via `squad-verify`, never in a workflow result or an engagement record.

6. **Build the workflow inputs (hard rule #4 — bake everything in).** Workflow scripts have no filesystem access, so assemble an `args` object from the live files:
   - `goal`: full text of `.squad/goal.md`.
   - `worldIndex` (hard rule #13): run `bash "${CLAUDE_PLUGIN_ROOT}/skills/squad-world/scripts/world.sh" --index` from the project root — the same squad-wide, script-projected text `squad-spawn`'s direct-`Agent` path bakes into every role's prompt (its step 9). If stdout is non-empty, set `args.worldIndex` to it verbatim — do not reformat, summarize, or re-derive it. **If stdout is empty (no `.squad/world/` at all, or nothing currently `live`), omit the `worldIndex` key from `args` entirely** — same absence contract as everywhere else this feature appears; never bake an empty section. This rides `args` the same way `goal` does — squad-wide, computed once, not per role.
   - `roles`: for each `active: true` role in `roster.json` (excluding any write-roles the user chose to hold back) → `{ name, roleGoal: <full text of .squad/role-goal-<name>.md>, fileScope: <roster file_scope>, task: <this-run contribution derived from the role purpose + the goal's definition of done>, model: <roster model or omit>, handoffs: <full text of each .squad/role-comm-*--<name>.md and --any.md with status: ready, if any survived step 5> }`.

7. **Author and run the workflow.** Follow the shape in `${CLAUDE_PLUGIN_ROOT}/templates/squad-dispatch.workflow.js` (read it). Author the script (or pass that template's logic) and run it via the Workflow tool with the `args` you built. The script fans out one `agent()` per role with `agentType` = the role name (so `.claude/agents/<name>.md` loads), each returning the `{role, summary, artifacts, status, follow_ups}` contract, then returns a structured digest.

8. **(Optional) persist.** If `--save` was passed, write the concrete script to `.claude/workflows/squad-dispatch.js` so it is committed and rerunnable (regenerate it whenever the roster changes — a saved script reflects the roster at generation time, not run time).

9. **Synthesize.** From the workflow's returned digest, read each role's artifacts from its `file_scope` and compose a user-facing report: what each role produced, where the artifacts live, what's `done` / `partial` / `blocked`, and the collected `follow_ups`. Surface any blocked role prominently — the digest's `status: "blocked"` is a fast signal, but it is synthesis, not the verdict (hard rule #10). Then hand off to `/cheeky-squad-os:squad-verify` to check the goal's Definition of done and write `.squad/verification.md`; a `met` verdict additionally requires `escalations_open == 0` (hard rule #14), so a blocked role's paired engagement record — not its structured result — is what actually gates it.

## Notes

- This command does **not** replace `/cheeky-squad-os:squad-spawn`. It is an optional, opt-in dispatch backend for One-time squads. `squad-spawn` remains the default and the only path for Multi-use and Evergreen.
- Resume is **in-session only** — if Claude Code exits mid-run, the next session starts the workflow fresh.
- The Workflow runtime contract this command relies on (script linting, `agent()`/`args` semantics, resume) is documented in [`docs/workflows-runtime-reference.md`](../docs/workflows-runtime-reference.md).

// =============================================================================
// squad-dispatch.workflow.js — cheeky-squad-os One-time dispatch as a Workflow
// =============================================================================
//
// This is the canonical SHAPE of a dynamic-Workflow dispatch for a One-time
// squad. `/cheeky-squad-os:squad-workflow` (and squad-spawn's optional Workflow
// path) author a concrete copy of this script from the LIVE roster and run it.
//
// WHY a workflow (vs the default "send N Agent calls and hand-synthesize"):
//   - Deterministic fan-out: one agent per active role, every run, no reliance
//     on the orchestrator remembering to batch the calls.
//   - Structured hand-off: each role returns a schema'd result, so synthesis is
//     mechanical instead of free-text scraping.
//   - Intermediate results live in `results` (a script variable), not the
//     orchestrator's context window — the main session only sees the final
//     synthesis.
//   - Resumable within the same Claude Code session.
//
// HARD CONSTRAINTS (verified against the Claude Code workflows doc) that shaped
// this design — do not "fix" them away:
//   - Workflow scripts have NO filesystem access. They cannot read
//     .squad/goal.md or roster.json. So everything the agents need is passed in
//     via `args` (baked by the runner — this IS hard rule #4) and/or read by the
//     agents themselves (they are real subagents and have the Read tool).
//   - The subagents a workflow spawns ALWAYS run in acceptEdits — their file
//     edits are auto-approved, which BYPASSES the PermissionRequest file-scope
//     hook. Compensating control: this template fans out READ/ANALYZE roles that
//     write deliverables ONLY inside their own file_scope, and every agent
//     prompt states that boundary explicitly. Roles that must mutate shared code
//     should stay on the hook-gated squad-spawn path, or run as their own
//     write-stage workflow with a human sign-off gate between stages.
//   - No mid-run user input. Onboarding / role generation stay interactive
//     skills; only the (already fully-specified) dispatch runs as a workflow.
//
// INPUT — `args` (supplied by the runner; never read from disk):
//   {
//     "goal": "<full text of .squad/goal.md>",
//     "roles": [
//       {
//         "name": "klaviyo-data-puller",      // matches .claude/agents/<name>.md
//         "roleGoal": "<full text of .squad/role-goal-<name>.md>",
//         "fileScope": ["reports/klaviyo/**", "data/klaviyo/**"],
//         "task": "What this role contributes THIS run",
//         "model": "sonnet"                    // optional; omit to inherit
//       }
//     ]
//   }
// =============================================================================

export const meta = {
	name: "squad-dispatch",
	description:
		"Dispatch a One-time cheeky-squad-os squad: fan out one agent per active role (read/analyze, scoped writes), then synthesize.",
	phases: [{ title: "Dispatch" }, { title: "Synthesize" }],
};

const squad = args || {};
const goal =
	squad.goal ||
	"(no goal text supplied — refuse and ask the runner to bake .squad/goal.md into args.goal)";
const roles = Array.isArray(squad.roles) ? squad.roles : [];

if (!roles.length) {
	log("No active roles supplied in args.roles — nothing to dispatch.");
	return { error: 'empty-roster', dispatched: 0 }
}

// Structured hand-off contract every role returns — makes synthesis mechanical.
const ROLE_RESULT_SCHEMA = {
	type: "object",
	additionalProperties: false,
	required: ["role", "summary", "artifacts", "status", "follow_ups"],
	properties: {
		role: { type: "string" },
		summary: {
			type: "string",
			description: "what this role produced, in 2-4 sentences",
		},
		artifacts: {
			type: "array",
			items: { type: "string" },
			description: "paths written, all inside this role file_scope",
		},
		status: { type: "string", enum: ["done", "partial", "blocked"] },
		follow_ups: {
			type: "array",
			items: { type: "string" },
			description: "anything needing human judgment or a follow-on role",
		},
	},
};

// hard rule #4 — the full goal + role-goal text is the only reliable
// parent->worker channel. Bake it into the prompt; also tell the agent to
// re-read the files (belt and suspenders, since it has Read).
function spawnPrompt(role) {
	return `You are the ${role.name} teammate on a cheeky-squad-os squad, dispatched inside a dynamic workflow.

# Squad goal (binding north-star)
${goal}

# Your role's goal
${role.roleGoal || `(role goal not supplied — read .squad/role-goal-${role.name}.md before doing anything)`}

# Your file scope (HARD BOUNDARY)
${(role.fileScope || []).map((g) => `- ${g}`).join("\n") || "- (none declared)"}

You are running with file edits auto-approved (acceptEdits) — the squad's
PermissionRequest scope hook does NOT gate you here. Therefore you MUST police
your own scope: write deliverables ONLY to the paths above. Do not edit, move,
or delete anything outside your file scope. If the task seems to require it,
stop and record it in follow_ups instead.

Also read .squad/goal.md and .squad/role-goal-${role.name}.md directly to confirm context.

# Your task this run
${role.task || "Contribute your role's slice of the squad goal: produce the artifact your role owns and write it inside your file scope."}

Write your deliverables to files inside your scope (do not paste large artifacts
into your reply), then return the structured result.`;
}

// ---- Phase 1+2: fan out per role, synthesize as each completes -------------
// pipeline() runs each role through dispatch -> (no barrier) so synthesis notes
// accumulate independently; the final cross-role synthesis happens after.
phase("Dispatch");

const results = await parallel(
	roles.map(
		(role) => () =>
			agent(spawnPrompt(role), {
				label: `dispatch:${role.name}`,
				phase: "Dispatch",
				agentType: role.name, // loads .claude/agents/<name>.md
				model: role.model, // undefined => inherit
				schema: ROLE_RESULT_SCHEMA,
			})
				.then((r) => ({ ...r, role: r.role || role.name }))
				.catch(() => ({
					role: role.name,
					summary: "agent errored or was skipped",
					artifacts: [],
					status: "blocked",
					follow_ups: ["re-run this role; it did not return a result"],
				})),
	),
);

phase("Synthesize");

const countBy = (status) => results.filter((r) => r.status === status).length;

// Return a structured digest. The orchestrator turns this into the user-facing
// report (and squad-spawn's synthesis step can read each role's file_scope for
// the full artifacts). Intermediate per-role detail stayed in `results`, never
// in the main session's context.
return {
  dispatched: results.length,
  done: countBy("done"),
  partial: countBy("partial"),
  blocked: countBy("blocked"),
  roles: results,
  all_follow_ups: results.flatMap((r) =>
    (r.follow_ups || []).map((f) => `${r.role}: ${f}`),
  ),
};

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
// Full runtime contract (script linting, agent()/args semantics, resume):
// docs/workflows-runtime-reference.md.
//
// INPUT — `args` (supplied by the runner; never read from disk):
//   {
//     "goal": "<full text of .squad/goal.md>",
//     "worldIndex": "<verbatim stdout of world.sh --index>",  // optional;
//                          // hard rule #13. Squad-wide, computed ONCE by the
//                          // runner, identical in every role's prompt. OMIT
//                          // THE KEY ENTIRELY when that stdout was empty —
//                          // never "" and never a placeholder. The absence
//                          // contract is the same one every other
//                          // .squad/world/-touching surface honors.
//     "partner": "<full text of .squad/partner.md>",           // optional;
//                          // hard rule #12 — the human's own standing brief.
//                          // PROJECT-wide (not even squad-wide): read ONCE by
//                          // the runner, identical in every role's prompt.
//                          // OMIT THE KEY ENTIRELY when the file is absent or
//                          // empty — never "" and never a placeholder; the
//                          // absence contract is byte-identical prompts.
//                          // Baked, never re-read: the file is gitignored by
//                          // default, so a role cannot find it on disk. No
//                          // role ever WRITES it — squad-partner is its only
//                          // writer, and on this path acceptEdits means the
//                          // PermissionRequest reservation that enforces that
//                          // elsewhere is inert, so the prompt says so out
//                          // loud below.
//     "roles": [
//       {
//         "name": "klaviyo-data-puller",      // matches .claude/agents/<name>.md
//         "roleGoal": "<full text of .squad/role-goal-<name>.md>",
//         "fileScope": ["reports/klaviyo/**", "data/klaviyo/**"],
//         "task": "What this role contributes THIS run",
//         "model": "sonnet",                   // optional; omit to inherit
//         "handoffs": [                        // optional; full text of each
//           "<.squad/role-comm-*--<name>.md (or --any.md) with status: ready>"
//         ]                                    // baked by the runner — workflow
//       }                                      // scripts cannot read disk
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
// hard rule #13 — the shared world model. Squad-wide, so it is read once
// here rather than per role. Absent/blank collapses to "" and the whole
// section drops out of every prompt below; never render an empty heading.
const worldIndex =
	typeof squad.worldIndex === "string" ? squad.worldIndex.trim() : "";
// hard rule #12 — the human's own standing brief. Project-wide, so read once
// here rather than per role. Absent/blank collapses to "" and the whole
// section drops out of every prompt below; never render an empty heading.
const partner = typeof squad.partner === "string" ? squad.partner.trim() : "";

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
		status: {
			type: "string",
			enum: ["done", "partial", "blocked"],
			description:
				'"blocked" means a stop: bound fired — pair it with an engagement record at status: escalated (hard rules #14-#15); squad-verify trusts the record, not this field',
		},
		follow_ups: {
			type: "array",
			items: { type: "string" },
			description:
				"anything needing human judgment or a follow-on role; also carries the hard-rule-#12 tag lines when a partner model was baked in — '[surfaced-ask-first] …' and '[belief-check: …] confirmed | contradicted | could not test — …'",
		},
	},
};

// hard rule #4 — the full goal + role-goal text is the only reliable
// parent->worker channel. Bake it into the prompt; also tell the agent to
// re-read the files (belt and suspenders, since it has Read).
function spawnPrompt(role) {
	return `You are the ${role.name} role on a cheeky-squad-os squad, dispatched inside a dynamic workflow.

# Squad goal (binding north-star)
${goal}
${
	partner
		? `
# Partner model (hard rule #12) — the human's own standing brief
${partner}

Binding on this run, on top of what the file itself says:
- Decide vs. ask is a SURFACING rule, not a settling rule. An item listed
  under "Always ask first" is never yours to decide, however obvious the
  right call looks or however short you are on time. Do not quietly pick
  the safer option and move on. Add one line to your follow_ups for each
  one you hit, in exactly this shape:
  "[surfaced-ask-first] <the decision, one line> — <why it is ask-first>".
  An item under "Decide without me" is yours to settle and needs no line.
  If the file's Attention lines give a deadline tie-break and it actually
  applies this run, follow it and say so in the same line rather than
  silently improvising one.
- Surfacing versus stopping. Check your own stop conditions below. If the
  ask-first item you hit is named there as a "stop:" bound, it is a stop:
  end the run, write status: escalated and fired: <that bullet, verbatim>
  on your engagement record (hard rule #14), return status "blocked", AND
  add the [surfaced-ask-first] line — one event, two channels, not a
  choice between them. If it is NOT among your declared bounds (you carry
  at most four, so most ask-first items will not be), do not escalate and
  do not stop: leave that one decision unmade, carry on with everything
  that does not depend on it, say in your summary what you could not
  finish because of it, and add the line. Either way the decision reaches
  the human unmade; what differs is whether the rest of your work stops.
- Standing constraints bind this run exactly the way the squad goal above
  does — a hard boundary on your own work, not a preference to weigh
  against convenience.
- A belief to check is verified, not inherited. If your task actually
  touches one of the hypotheses under "Beliefs to check", test it rather
  than assume it still holds, and add one follow_ups line in exactly this
  shape: "[belief-check: <the belief, one line>] confirmed | contradicted
  | could not test — <the evidence, one line>". A belief you never touched
  needs no line; those three words are the only three that belong there.
  Both tag shapes ride follow_ups because that array is the only channel
  on this dispatch path that reaches the human's synthesis intact.
- This section was baked into your prompt once, at dispatch. Do not try to
  read .squad/partner.md — it is gitignored by default and you will not
  find it. Do NOT write it, ever: squad-partner is its only writer anywhere
  in this plugin, and a fact about the human that the human did not say is
  exactly what hard rule #12 exists to keep out of that file. Elsewhere in
  this plugin the PermissionRequest hook refuses that write structurally;
  on THIS path you run under acceptEdits, so nothing mechanically stops you
  — police it yourself, exactly as you police your file scope below.
`
		: ""
}
# Your role's goal
${role.roleGoal || `(role goal not supplied — read .squad/role-goal-${role.name}.md before doing anything)`}
${
	worldIndex
		? `
# Shared world model (hard rule #13) — what this squad already believes
${worldIndex}

Standing instructions for using it:
- Reuse an existing key rather than minting a near-duplicate — check the
  index above before writing a new "## Belief:" heading to your own claims
  file at .squad/world/claims-${role.name}.md.
- Never edit another owner's claims file. Only .squad/world/claims-${role.name}.md
  is yours. On this dispatch path you run under acceptEdits, so nothing
  mechanically stops you — police it yourself, exactly as you police your
  file scope below.
- Contest a belief by writing your own counter-block under the same key, in
  your own claims file — never by editing the block you disagree with. Two
  live blocks under one key from different owners ARE the dispute; nobody
  writes the word "disputed", including you.
- A key shown above as DISPUTED may not be silently picked. If your work
  depends on one, say in your engagement record's ## Assumptions which side
  you used and why.
- Every belief you write carries Claim, Source, Grade (confirmed | reported
  | inferred | assumed — the same four grades as your assumptions, never a
  number), and Observed. A block missing any of them is parsed as invalid
  and reaches no prompt, ever — so an unsourced belief is not a shortcut,
  it is a write that did nothing.
- This file is never cleared between dispatches — unlike your engagement
  record and the hand-offs, what is written here accumulates for the life of
  the squad.
`
		: ""
}
# Your file scope (HARD BOUNDARY)
${(role.fileScope || []).map((g) => `- ${g}`).join("\n") || "- (none declared)"}
${
	(role.handoffs || []).length
		? `
# Incoming hand-offs (from upstream roles — honor their Caveats sections)
${role.handoffs.join("\n\n---\n\n")}
`
		: ""
}

# Step 0 (hard rule #11) — publish your engagement record BEFORE any other write
Before writing anything else — including your deliverables — publish your
engagement record at .squad/role-plan-${role.name}.md, following the schema in
templates/role-plan.md exactly: frontmatter (role: ${role.name}, created,
status: active), then the sections ## Task read, ## Intended approach,
## Deliverables, ## Assumptions, ## Amendments. Grade every assumption by
evidence class, never by a confidence number — [confirmed] names the file,
command, or URL that proves it; [reported] names the source (goal / hand-off
/ artifact / human); [inferred] says how you reasoned to it; [assumed] names
what breaks if wrong, as "if wrong → <deliverable or Definition-of-done
signal>". If your read of the task diverges from your role goal above, say so
here — that divergence is the headline, not a footnote.

Note for this dispatch path: you run under acceptEdits (see below), so the
PermissionRequest plan gate that defers an ungated role's writes elsewhere in
this plugin is inert for you — nothing here mechanically blocks a skipped
Step 0. Publish the record anyway. It is what squad-verify's Process table
and this run's synthesis diff (declared-vs-produced) read; skipping it makes
your run's reasoning invisible to the human afterward, even though your
files still land.

# If a stop: bound fires (hard rules #14-#15)
Your role goal above may declare a "## Stop conditions" section. If one of
its stop: bounds fires while you work, do not push through it and do not
quietly stop: rewrite your engagement record's frontmatter to
status: escalated and fired: <the bullet that fired, verbatim>, then fill
three sections exactly as templates/role-plan.md describes for the
direct-Agent dispatch path — ## What happened (which condition fired, on
what evidence, at which step), ## State of the work (per declared
deliverable: complete / partial: <gap> / untouched), ## What would unblock
(the smallest grant, file, or ruling that resumes you). That record is your
only hand-back. Also set status: "blocked" on the structured result you
return below, so the two agree: this run's synthesis reads your result
immediately, but squad-verify and any later re-verify trust only the
record, not your prose. There is no "resolved" status and no "resolution:"
field anywhere in that schema for you to write, on this path or any other —
whether an escalation is resolved is the human's ruling, recorded only in
.squad/verification.md by squad-verify. Do not return status: "done" or
"partial" while a stop: bound is live and unrecorded.

You are running with file edits auto-approved (acceptEdits) — the squad's
PermissionRequest scope hook does NOT gate you here. Therefore you MUST police
your own scope: write deliverables ONLY to the paths above. Do not edit, move,
or delete anything outside your file scope. If the task seems to require it,
stop and record it in follow_ups instead.

Also read .squad/goal.md and .squad/role-goal-${role.name}.md directly to confirm context.

# Your task this run
${role.task || "Contribute your role's slice of the squad goal: produce the artifact your role owns and write it inside your file scope."}

Write your deliverables to files inside your scope (do not paste large artifacts
into your reply). When a deliverable is ready for another role, also publish a
hand-off manifest at .squad/role-comm-${role.name}--<consumer>.md (shape:
templates/role-comm.md — what's ready, how to consume, caveats); a later stage
or run will deliver it. Then return the structured result.`;
}

// ---- Phase 1: fan out one agent per role (barrier), then synthesize --------
// parallel() is the right primitive here, not pipeline(): dispatch is a single
// stage and the synthesis below genuinely needs ALL role results at once (it
// counts statuses and merges every role's follow_ups). A thunk that throws
// resolves to its .catch() fallback below, so the barrier never rejects.
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

// hard rule #12 — the partnership receipt's fourth counter, on this path.
// Roles were told to tag ask-first surfaces and belief checks in follow_ups
// (the only channel that survives to synthesis here); these just count and
// collect them. No partner model in args => no tags => 0 and [], and the
// orchestrator prints nothing, exactly as with an absent partner.md on the
// direct-Agent path. Nothing here ever WRITES .squad/partner.md.
const taggedFollowUps = (tag) =>
	results.flatMap((r) =>
		(r.follow_ups || [])
			.filter((f) => typeof f === "string" && f.trim().startsWith(tag))
			.map((f) => `${r.role}: ${f.trim()}`),
	);
const askFirstSurfaced = taggedFollowUps("[surfaced-ask-first]");
const beliefChecks = taggedFollowUps("[belief-check:");

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
  // hard rule #12. Both keys are ALWAYS present with their honest value —
  // [] and 0 when there was no partner model, or when no role's task ever
  // touched one. The "earn the sentence or skip it" rule lives in the
  // orchestrator's receipt (squad-spawn's synthesis), not here: a digest
  // that omitted the key would be indistinguishable from a build that never
  // shipped the counter.
  ask_first_surfaced: askFirstSurfaced,
  ask_first_surfaced_count: askFirstSurfaced.length,
  belief_checks: beliefChecks,
};

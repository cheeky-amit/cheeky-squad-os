# Roadmap — the path to "the only plugin you'll ever need"

The north star is unfalsifiable as stated, so we hold it to the plugin's own discipline:
reformulate as measurable signals, gather evidence, and let verification decide.
Synthesis summarizes; verification decides — that applies to the product too.

## The measurable definition

cheeky-squad-os is "the only plugin someone will ever need" when, for any goal-driven
work in Claude Code — engineering, ops, business infrastructure, knowledge work — it
covers the full lifecycle with nothing missing that a second plugin would have to supply:

| Pillar (from the tagline) | Signal | Status |
| --- | --- | --- |
| **Roles** | Bespoke roles generated from any goal; zero shipped role files bias the shape | ✅ v0.1.0 (`squad-role`, `squad-onboard`) |
| **Responsibilities** | Per-role `file_scope` + role goals, mechanically enforced by the `PermissionRequest` hook | ✅ v0.1.0; glob matcher hardened in v0.2.0 |
| **Environments** | Sandbox-scoped provisioning; propose what can't be contained | ✅ v0.1.0 (`squad-env`, hard rules #8–#9) |
| **Communication** | Goal/role-goal prompt-baking (parent→worker) ✅; structured worker↔worker hand-offs via `.squad/role-comm-<from>--<to>.md` manifests (outbox auto-approved, forging defers, ready manifests baked into downstream spawn prompts) | ✅ v0.3.0 (`templates/role-comm.md`) |
| **Supervision** | Definition-of-done verification with an artifact of record | ✅ v0.2.0 (`squad-verify`, hard rule #10) |
| **All three cadences** | One-time / Multi-use / Evergreen, each with a real dispatch path | ✅ v0.1.0; Evergreen depends on external schedulers — see gap 4 |
| **Trustworthy by inspection** | Docs match shipped behavior; examples conform to real schemas; CI proves it | ✅ v0.2.0 (truth sync + example-roster lint) |
| **Domain grounding** | Optional guided research grounds workstream decomposition in checked facts instead of priors alone: two human gates, four independently-degrading source classes, a per-owner grade ceiling `world.sh` enforces mechanically, and a composition loop (rewrite rules, citations, a delta line) that a model can't fake by decorating priors with belief keys | ✅ v1.0.0 (`squad-world`'s **research** verb; `squad-onboard`/`squad-role` composition loop) |
| **Partnership** | The human is modeled and bound too, not only the squad: a declared engagement record before a role's first write (#11), a partner model the human dictates and confirms (#12), a shared belief ledger with sourced, graded claims (#13), self-policed stop conditions on every role (#14), and an evidence bar — `PASS (attested)` — the human meets at verification the same way a role does (#15) | ✅ v1.0.0 (`squad-partner`, `squad-world`, `squad-role`'s Stop conditions, `verify.sh` attestation) |

## Ranked gaps (what a 0.3.0+ should close)

1. ~~**Communication v2 — structured hand-offs.**~~ **Shipped in v0.3.0**: the
   `.squad/role-comm-*` namespace is now the hand-off contract — producer publishes a
   manifest (what's ready / how to consume / caveats) to its hook-scoped outbox;
   `squad-spawn` bakes ready manifests into downstream spawn prompts (One-time) and
   teammates pair live messages with the durable manifest (Multi-use).
2. **Verification depth — executable evidence.** `squad-verify` judges signals from file
   evidence. Let a Definition-of-done bullet declare an evidence command
   (e.g. `verify: bats tests/`), which `verify.sh` runs read-only and records
   pass/fail per signal. Turns NEEDS-HUMAN into PASS/FAIL for testable goals.
3. **Goal-drift enforcement option.** `UserPromptSubmit` is observational in v1.
   Add an opt-in strict mode: when a turn's intent contradicts `goal.md`, the hook
   asks for an explicit goal amendment instead of silently tagging.
4. **Evergreen ergonomics.** The plugin prints scheduler instructions but can't create
   durable schedules. Track Claude Code's scheduling surfaces (routines, desktop tasks)
   and integrate first-class as soon as a plugin-accessible API exists.
5. **Mode escalation.** A One-time squad that proves recurring value currently requires
   re-onboarding. Ship a guided `one-time → multi-use/evergreen` migration that
   preserves roles, scopes, and role goals.
6. **Marketplace presence.** Publish to a public marketplace listing with the smoke test
   as the acceptance gate, so install friction never makes someone reach for an
   alternative.
7. **Roster sync.** All state is local under `.squad/`. Optional remote sync for squads
   shared across machines/teammates (already noted as a non-goal in ARCHITECTURE — it
   graduates to a goal here).
8. **Plan-gated two-stage dispatch.** Deferred from the v1.0 design, not from this
   feature specifically — the keep/kill review cut it because it doubles dispatch cost
   for the gated role and recurs as a decline-by-default offer every engagement; the
   engagement record, hook gate, and verify integration already stand without it. What
   it would add: a role writes its plan (`status: proposed`), the human reviews and
   approves it, and only then does stage two dispatch and execute — the one true pre-act
   review the subagent execution model can support, versus the declared-intent-and-audit
   trail this plugin ships today. v1.1, on demand; the `proposed` status returns with it.
9. **The §5.2 self-report signal.** A role self-attesting something at `squad-verify`
   time — distinct from the engagement record it already publishes before acting —
   considered during the v1.0 design and deferred: one more question at the flow's
   already-named abandonment point (verification), consumed by nothing yet. v1.1
   candidate.
10. **`TeammateIdle` / `TaskCompleted` forcing hooks.** Today's hooks (`SessionStart`,
    `UserPromptSubmit`, `PermissionRequest`) cover session start, every turn, and every
    file write — nothing fires on a teammate going idle or finishing a task, so hard
    rules #11/#14's checks depend on the role's own cooperation on the Multi-use path
    the same way a subagent's do. Contingent on Agent Teams graduating from
    experimental — building against an experimental surface's lifecycle events risks
    a hook wired to an event that changes shape before it stabilizes. v1.1 candidate.

Closed outside the ranked list (v0.4.0): workflow-path manifest parity (`/squad-workflow`
bakes `args.handoffs`), manifest staleness semantics (dispatchers clear per-engagement
manifests; `--chain` preserves them for follow-on stages), and the single-squad
assumption (park/switch whole squads under `.squad/squads/<slug>/`).

## How releases are judged

Each release must move at least one pillar's status, keep CI green — one workflow
job (`shell`) running five checks as of v1.0.0: shellcheck, `bats tests/*.bats`,
`tests/mermaid-lint.sh`, `node --check` on the workflow dispatch template, and the
example-roster schema lint — update
CHANGELOG.md, and leave the docs truthful — a release that ships behavior the
README doesn't describe (or vice versa) fails its own Definition of done.

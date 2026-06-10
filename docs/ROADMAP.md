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

## How releases are judged

Each release must move at least one pillar's status, keep CI green
(shellcheck + bats + example-roster lint), update CHANGELOG.md, and leave the docs
truthful — a release that ships behavior the README doesn't describe (or vice versa)
fails its own Definition of done.

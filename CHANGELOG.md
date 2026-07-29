# Changelog

All notable changes to cheeky-squad-os are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [0.4.1] - 2026-07-29

Security release. One hook change, one guarantee restored, no new features.

### Security

- **Squad state was writable by any broadly-scoped role.** `hooks/permission-request.sh` matched every path against the role's `file_scope`, including paths under `.squad/`. A role whose scope was broad — `**`, or `.squad/**` — therefore had its writes to *other roles' state* auto-approved, with no permission prompt: another role's hand-off outbox, another role's `role-goal-*`, `goal.md`, `roster.json`, and `verification.md`.

  Two of this project's stated guarantees were affected. The v0.3.0 note below claims the segment-aware matcher makes forged hand-offs "structurally impossible to auto-approve" — that held only for roles whose `file_scope` happened to be narrow, and is corrected here. And hard rule #10, "synthesis summarizes, verification decides," was defeasible: a broadly-scoped role could write its own `verification.md`.

  **Fixed by the `.squad/` structural reservation.** A path under `.squad/` no longer consults `file_scope` at all. A role is auto-approved for exactly the paths *derived from its own `agent_type`* — its own outbox (`.squad/role-comm-<role>--*`) and its own declared `environment.workspace` — and every other `.squad/` write defers to the human, at any scope. Reserved artifacts (`goal.md`, `roster.json`, `roster.md`, `verification.md`, `role-goal-*`, `role-comm-*`, `role-plan-*`, `world/*`, `squads/*`) are checked *before* the sandbox grant, so a roster that declares a workspace of `.squad/` cannot swallow another role's contract paths either. 14 new bats cases, including a broad-scope (`**`) fixture role that must fail to reach any of it.

  **Honest accounting:** this both widens and narrows. A role now gets its own outbox and sandbox structurally, whether or not they were registered in `file_scope` — two derived, unforgeable paths the hook did not previously grant on its own. Everything else under `.squad/` is narrowed. The old invariant "the hook can only ever remove an auto-approval" no longer holds; the new one is "the hook can only ever grant a role its own state."

  No action is required on upgrade. Rosters that already register `.squad/role-comm-<role>--*` or a `.squad/workspaces/<role>/**` scope keep working unchanged — those grants are now structural rather than declared.

### Fixed

- Version drift: `.claude-plugin/marketplace.json` still advertised `0.1.0` while the plugin manifest was at `0.4.0`. Both now track the release.

## [0.4.0] - 2026-06-10

The lifecycle release: hand-off channel completeness and multi-initiative projects.

### Added

- **Multi-squad via park/switch** — `squad-goal` gains `park`, `switch`, and `list squads`: the active squad's durable state (goal, roster, role-goals, verification, role files) moves to `.squad/squads/<slug>/` and back, so one project can hold several initiatives without concurrent-squad collisions. The active squad always lives at `.squad/` — hooks, scripts, and tests stay single-squad readers with zero changes. `squad-onboard` and `squad-goal`'s replace flow now offer parking instead of destruction.
- **Workflow dispatch carries manifests** — `/squad-workflow` bakes ready hand-off manifests into each role's `args.handoffs`, and `templates/squad-dispatch.workflow.js` renders them as an "Incoming hand-offs" prompt section and instructs roles to publish their own. The workflow path and the direct-`Agent` path now speak the same communication channel.

### Fixed

- **Manifest staleness semantics** — manifests are per-engagement: `squad-spawn` clears leftovers before each fresh dispatch (including every Evergreen iteration) and `/squad-workflow` does the same unless the new `--chain` flag marks the run as a follow-on stage consuming the previous stage's hand-offs. A role can no longer be baked a stale manifest from a completed prior run.

## [0.3.0] - 2026-06-10

The communication release. The last amber pillar of the tagline ("roles, responsibilities, communication, and supervision") — structured worker↔worker hand-offs, implementing the `.squad/role-comm-*` namespace reserved since v0.1.0.

### Added

- **Hand-off manifest channel** — when a role's deliverable is ready for a downstream role, it publishes `.squad/role-comm-<from>--<to>.md` (shape: new `templates/role-comm.md`): frontmatter (`from`/`to`/`created`/`status`), *What's ready* (artifact paths), *How to consume*, *Caveats*. Ephemeral, per-run, gitignored.
- **Outbox scoping** — `squad-role` now always registers `.squad/role-comm-<name>--*` in each role's `file_scope`. Publishing to your own outbox auto-approves; writing another role's outbox defers — the segment-aware glob matcher (v0.2.0) makes forged hand-offs structurally impossible to auto-approve. 2 new bats cases prove it.
  > **Corrected in v0.4.1:** this held only for roles whose `file_scope` was narrow. A role scoped `**` matched another role's outbox and was auto-approved. The guarantee is real as of the `.squad/` structural reservation — see the v0.4.1 security note above.
- **Mode-appropriate delivery** — `squad-spawn` globs `.squad/role-comm-*--<role>.md` before dispatching a downstream role and bakes every `status: ready` manifest into its spawn prompt (subagents can't receive messages mid-run — manifests ride the hard-rule-#4 prompt-baking channel). Multi-use teammates message live via Agent Teams and keep the manifest as the durable record; generated roles get inbox/outbox instructions via `templates/role-definition.md`.

### Changed

- ARCHITECTURE/LOGIC/README/CONTRIBUTING document the channel; template count is now 7; `docs/ROADMAP.md` communication pillar flipped to shipped.

## [0.2.0] - 2026-06-10

The supervision release. The tagline always promised "roles, responsibilities, communication, and supervision" — this version ships the supervision component.

### Added

- **`squad-verify` skill** — the seventh skill, closing the loop after dispatch. Checks every bullet of the goal's `## Definition of done` against the squad's actual deliverables, marks each signal PASS / FAIL / NEEDS-HUMAN (evidence or NEEDS-HUMAN — never a guess), and writes `.squad/verification.md` with a met / partial / unmet verdict. Read-only judging: it never modifies `goal.md` or `roster.json`.
- **`skills/squad-verify/scripts/verify.sh`** — jq-based evidence scaffold emitting JSON lines: one per Definition-of-done signal, one per active role (deliverable counts under `file_scope`, role-goal presence), plus a summary line. Skips YAML frontmatter and HTML comments when parsing the goal.
- **`templates/verification.md`** — the report skeleton (per-signal sections, role-deliverables table, verdict frontmatter).
- **Hard rule #10** — "Synthesis summarizes, verification decides": `.squad/verification.md` is the only authority for declaring the goal met. `squad-spawn`'s per-spawn synthesis and `/squad-workflow`'s digest now end by handing off to `squad-verify`.
- **`tests/verify.bats`** — 14 automated cases covering preflight refusals, Definition-of-done parsing (frontmatter/HTML-comment exclusion), glob scope counting, inactive-role skipping, and JSON-lines validity.
- **CI example-roster schema lint** — every fenced roster JSON block in `examples/*.md` is validated against the canonical `roster.json` schema. Invented keys (`allowed_paths`, `depends_on`, `schema_version`, …) silently disable the permission hook, so they now fail the build.
- **`docs/workflows-runtime-reference.md`** — verified runtime reference for the dynamic-Workflow DSL behind `templates/squad-dispatch.workflow.js`.

### Fixed

- **Permission hook mid-path glob over-approval** — a `file_scope` glob like `data/*` previously matched `data/sub/secret` because bash `[[ == ]]` lets `*` cross `/`. The matcher now requires segment-for-segment matching (`*` never crosses `/`); `prefix/**` remains the way to grant a subtree.
- **Example rosters rewritten to the canonical schema** — all three walkthroughs (`klaviyo-audit`, `landing-page-redesign`, `weekly-competitive-intel`) previously showed invented roster keys and role-frontmatter fields that the hook and spawn path never read. They now match `templates/roster.json` and the subagent frontmatter spec exactly.
- **Docs truth sync** — README's hooks story now matches the shipped hook (in-sandbox scaffolding Bash auto-approves; it is no longer claimed that "Bash always defers"); component counts corrected to 7 skills / 6 templates; `squad-roster` no longer claims the PermissionRequest hook calls it (the hook reads `roster.json` directly); stale "Phase 7" / original-brief references removed; roster schema docs now include the `environment` block.
- **`tests/permission-request.bats`** — allow assertions are now structural (`jq -e '.hookSpecificOutput.decision.behavior == "allow"'`) instead of substring matches; 4 new mid-path glob cases.

## [0.1.0] - 2026-06-08

Initial release: 6 skills (`squad-onboard`, `squad-goal`, `squad-role`, `squad-env`, `squad-spawn`, `squad-roster`), 3 hooks (SessionStart goal injection, UserPromptSubmit goal tagging, PermissionRequest scoped auto-approval), 3 modes (One-time / Multi-use / Evergreen), role environments with sandbox-scoped provisioning, optional dynamic-Workflow dispatch, zero shipped role files.

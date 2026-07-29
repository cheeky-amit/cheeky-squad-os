# Changelog

All notable changes to cheeky-squad-os are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

Work toward 1.0.0 — "the partnership release". Entries accumulate here and the version bumps once, when the release lands.

### Added

- **Hard rule #11 — plan before act. The engagement record.** A role now publishes `.squad/role-plan-<role>.md` — its read of the task, its intended approach, the exact deliverables it will produce, and its assumptions — **before its first write to anything else**. Until that record exists, the `PermissionRequest` hook defers the role's in-scope Edit/Write, its in-sandbox Bash, and its hand-off outbox. It never denies: a role that declines to declare gets exactly the behavior an out-of-scope write got before, so no roster needs migrating. The record's own path is granted unconditionally — a role cannot publish its plan if publishing the plan required a plan. *Autonomy is purchased with intent.*

  **Uncertainty is graded by evidence class, never by number.** A role cannot derive "73% confident", so a number would be theatre. Every assumption carries one of four grades and each owes something: `[confirmed]` names the file, command, or URL that proves it · `[reported]` names the source · `[inferred]` says how · `[assumed]` names what breaks, as `if wrong → <deliverable or Definition-of-done signal>`. That last clause is load-bearing: **`squad-verify` refuses to PASS a Definition-of-done signal resting on the same role's `[assumed]` bullet** — it is at most NEEDS-HUMAN, with the guess quoted verbatim. Naming the blast radius is what makes a guess reviewable instead of invisible.

  `squad-spawn` bakes the record as Step 0 of every dispatch (all three modes, the fallback path, and the workflow path), clears the records of **only the roles it is dispatching**, and its synthesis diffs declared-versus-produced. `squad-verify` gains a `## Process` section — evidence about *how* the work was done, not only what it produced. `spawn.sh collect` brings records back from worktree-isolated roles, since a gitignored record is never carried by a merge.

- **Hard rules #14 and #15 — declared bounds, and the evidence bar the human meets too.** Every role now declares 2–4 `## Stop conditions` in its role goal, derived by `squad-role` from purpose, tools, and the squad goal's `Out of scope` — **no new question is added to the flow**. Each bullet carries exactly one of two verbs: `needs:` is a precondition (`squad-spawn`'s dispatch triage probes what it can, informationally — it never gates), `stop:` is a mid-run bound the role **self-polices**; nothing external monitors it, and the docs say so. A fired `stop:` bound ends the run with `status: escalated` and `fired: <the bullet, verbatim>` on the engagement record, plus three hand-back sections — `## What happened`, `## State of the work`, `## What would unblock`. *Stopping well is a deliverable.*

  **An open escalation blocks a `met` verdict**, and only the human's recorded ruling closes one. `verify.sh` computes `escalations_open` mechanically, as a set difference over two inputs neither of which a role controls: the `status: escalated` records, minus the roles named in `.squad/verification.md`'s `resolved_escalations`. A NEEDS-HUMAN row or an open escalation converts to PASS only against a stated what-you-checked / what-you-found, recorded verbatim with attribution and date and marked `PASS (attested)` — permanently distinct from machine-verified truth. A bare assertion earns exactly one push-back, then goes on the record anyway: **the human is never blocked, they are put on the record.** This is the first rule in the repo's history that binds the human rather than the squad.

  **The load-bearing invariant: a role can never mint the human's ruling.** The engagement record's status enum stops at `active | amended | escalated` — there is no `resolved` status and no `resolution:` field anywhere a role writes, on any dispatch path. Stated honestly and not papered over: a role *can* flip its own `escalated` back to `active`, which is behaviorally identical to never having stopped — the acknowledged aspirational half of #14. What it cannot do is manufacture the ruling.

  Numbering is append-only: **#12 and #13 are deliberately unused**, reserved for a later release, and are documented nowhere as existing.

### Fixed

- **The `.squad/` reservation was defeated by a `./` prefix.** `hooks/permission-request.sh` enforced the reservation with a textual prefix test that recognized exactly one spelling. `./.squad/verification.md`, `.//.squad/…`, and absolute paths containing `/./` or `//` all name the same file as `.squad/verification.md`, but missed the test, fell through to `file_scope`, and were auto-approved for any role scoped `**`. That is the v0.4.1 forgery hole reopened by two characters — and the file it reached is the one the human's ruling lives in, so a role could have cleared its own escalation and unblocked a `met` verdict (hard rules #10, #14). Paths are now normalized before any containment test: `//`, `/./`, and a leading `./` are collapsed; `..` is still never resolved, only rejected.

- **The scaffolding-Bash surface never consulted the reservation at all.** That surface tested operands against the role's `environment.workspace` prefix alone, bypassing `squad_grant`. A roster declaring `workspace: ".squad"` therefore made every reserved path a sandbox path on that surface: `cp forged.md .squad/verification.md`, `ln -f`, and `touch` over `verification.md`, `goal.md`, `roster.json`, and another role's engagement record were all auto-approved — while the *identical* Edit/Write was correctly deferred, as it has been since v0.4.1. `.squad/` operands now take the same `squad_grant` decision on both surfaces. A role's own record, own outbox, and ordinary nested sandboxes are unaffected.

- **A recorded human ruling was silently ignored when written in canonical YAML.** `verify.sh`'s `resolved_escalations` parser required the block-style dash at column 0, so the two-space-indented list that `templates/verification.md` and `examples/klaviyo-audit.md` both document never matched. The subtraction found nothing to subtract, `escalations_open` stayed above zero forever, and `met` became unreachable no matter what the human ruled. Indentation is now accepted; flow style still is too.

- **Worktree-isolated roles could lose auto-approval entirely.** The hook resolved both the roster and its containment root from `$CLAUDE_PROJECT_DIR`. For a role running under `isolation: worktree` (hard rule #7), that variable may point at the main checkout while the role's `.squad/` lives in the worktree — in which case the hook found no roster, deferred every write, and additionally rejected absolute worktree paths as outside the project. It now resolves to whichever of `$CLAUDE_PROJECT_DIR` or the hook input's `cwd` actually holds `.squad/roster.json`, and defers exactly as before when neither does.

### Changed

- **Runtime truth sync.** v0.4.0's docs were written 2026-06-10 and several claims had gone stale. Re-verified against live documentation on 2026-07-29 and corrected across `ARCHITECTURE.md`, `LOGIC.md`, `README.md`, `CONTRIBUTING.md`, `docs/workflows-runtime-reference.md`, `commands/squad-workflow.md`, the skills, the templates, and the examples:
  - **Role `model` values** — the documented set is now `sonnet | opus | haiku | fable | inherit`, or a full model ID (e.g. `claude-opus-5`). The repo's `sonnet | opus | haiku | inherit` was wrong twice: it omitted the `fable` alias and it omitted full IDs.
  - **Role `effort`** — subagent frontmatter now supports a per-role reasoning-effort tier (`low`/`medium`/`high`/`xhigh`/`max`, availability gated by model). `squad-role` asks for it only when it would change something, `templates/role-definition.md` renders it, and `roster.json` records it. **Optional everywhere** — a role with no `effort` is valid and behaves exactly as before.
  - **Dynamic Workflows** are no longer a research preview: v2.1.154+, on all paid plans, with Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform and Microsoft Foundry (on Pro, enabled from `/config`). Still org-disablable; the graceful fallback is unchanged. The runtime reference gains the current `agent()` option surface, the concurrency and total-agent limits, corrected resume semantics, and confirmation that workflow nesting exists at exactly one level.
  - **`isolation: worktree`** — noted that the platform now *enforces* worktree containment (v2.1.203/2.1.216) rather than relying on the subagent's cooperation, which is hard rule #7 getting a real backstop.
  - **Agent Teams remains experimental and env-gated** — unchanged, and deliberately not "modernized". What is new is a documented trap: a role's own `hooks:` frontmatter does **not** fire when that role runs as a teammate, so enforcement must live in the plugin's project-level hooks (which do fire, because a teammate is a full session). A teammate also inherits the lead's `effort`, not the role file's.

- **`acceptEdits` on the workflow path — honesty fix.** `commands/squad-workflow.md` and `skills/squad-spawn/SKILL.md` asserted that workflow subagents "bypass the `PermissionRequest` file-scope hook". Whether the hook never fires there, or fires and is overridden by `acceptEdits`, is not established — so both now state only what is certain: workflow subagents run in `acceptEdits`, their file edits are auto-approved, and **a role's writes are therefore not gated by its `file_scope` on that path**. The compensating design (fan out read/analyze roles; keep code-mutating roles on the hook-gated `squad-spawn` path) is unchanged.

- **CI runs `bats tests/*.bats`** instead of an explicit four-file list, so a new suite can never be silently unwired by someone forgetting to register it.

### Fixed

- **`squad-roster` rejected valid roles.** Roster validation required `model` to be one of `sonnet`/`opus`/`haiku`/`inherit`, so a role using the `fable` alias or a full model ID failed audit. It now accepts the documented set, plus an optional `effort` value.

### Removed

- **`.squad/features/*`** — reserved in v0.1.0, never defined, never used. Retired rather than carried forward undefined.

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

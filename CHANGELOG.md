# Changelog

All notable changes to cheeky-squad-os are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [1.0.0] - 2026-07-30

The partnership release. v0.x wrote the squad's obligations to the goal — bespoke
roles, scoped responsibilities, structured hand-offs, a verified Definition of done.
v1.0 writes the obligations the human and the squad owe *each other*, and for the
first time, one rule binds the human, not the squad.

**Five hard rules, each with a shipped mechanism:**

| Rule | Law | Mechanism |
| --- | --- | --- |
| **#11** | Autonomy is purchased with intent. | `.squad/role-plan-<role>.md`, the engagement record |
| **#12** | Told, not inferred. | `.squad/partner.md`, written only by `squad-partner` |
| **#13** | A belief with no source is a rumor. | `.squad/world/claims-<owner>.md`, parsed by `world.sh` |
| **#14** | Stopping well is a deliverable. | `## Stop conditions` + `status: escalated` engagement records |
| **#15** | The human meets the same evidence bar. | `PASS (attested)` in `.squad/verification.md` |

Two new skills — `squad-world` (shared world model + guided research) and
`squad-partner` (the partner model) — take skills 7 → 9. Templates 7 → 10
(`role-plan.md`, `partner.md`, `world-claims.md` are new). Hooks hold at 3.
`bats` grows 79 → 238 across 6 suites (up from 4 suites at 0.4.1); CI grows
from 3 checks to 5 (mermaid-lint and `node --check` on the workflow template
are new).

**Four defects in previously-shipped code**, found and closed before this release:

- the `.squad/` reservation's forgery hole, reopened by a `./` path prefix, plus its
  two follow-on paths — the scaffolding-Bash surface never consulting the
  reservation at all, and a legitimate human ruling silently ignored when recorded
  in canonical (indented) YAML;
- worktree-isolated roles losing auto-approval entirely when `$CLAUDE_PROJECT_DIR`
  pointed at the main checkout instead of the worktree holding `.squad/`;
- four mermaid `sequenceDiagram` blocks (`ARCHITECTURE.md`, `LOGIC.md`,
  `LOGIC.local.md`, `docs/workflows-runtime-reference.md`) that had never
  rendered on GitHub, now guarded by `tests/mermaid-lint.sh` in CI;
- `templates/squad-dispatch.workflow.js`, shipped JavaScript CI never
  syntax-checked, now gated by `node --check`.

One novelty claim, hedged: to the best of a search at the time of writing, no
other agent-orchestration framework ships the Collins et al. (arXiv:2408.03943)
desiderata as working infrastructure rather than as a citation. Search coverage
is not proof, and we did not attempt an exhaustive one.

### Added

- **Hard rule #11 — plan before act. The engagement record.** A role now publishes `.squad/role-plan-<role>.md` — its read of the task, its intended approach, the exact deliverables it will produce, and its assumptions — **before its first write to anything else**. Until that record exists, the `PermissionRequest` hook defers the role's in-scope Edit/Write, its in-sandbox Bash, and its hand-off outbox. It never denies: a role that declines to declare gets exactly the behavior an out-of-scope write got before, so no roster needs migrating. The record's own path is granted unconditionally — a role cannot publish its plan if publishing the plan required a plan. *Autonomy is purchased with intent.*

  **Uncertainty is graded by evidence class, never by number.** A role cannot derive "73% confident", so a number would be theatre. Every assumption carries one of four grades and each owes something: `[confirmed]` names the file, command, or URL that proves it · `[reported]` names the source · `[inferred]` says how · `[assumed]` names what breaks, as `if wrong → <deliverable or Definition-of-done signal>`. That last clause is load-bearing: **`squad-verify` refuses to PASS a Definition-of-done signal resting on the same role's `[assumed]` bullet** — it is at most NEEDS-HUMAN, with the guess quoted verbatim. Naming the blast radius is what makes a guess reviewable instead of invisible.

  `squad-spawn` bakes the record as Step 0 of every dispatch (all three modes, the fallback path, and the workflow path), clears the records of **only the roles it is dispatching**, and its synthesis diffs declared-versus-produced. `squad-verify` gains a `## Process` section — evidence about *how* the work was done, not only what it produced. `spawn.sh collect` brings records back from worktree-isolated roles, since a gitignored record is never carried by a merge.

- **Hard rules #14 and #15 — declared bounds, and the evidence bar the human meets too.** Every role now declares 2–4 `## Stop conditions` in its role goal, derived by `squad-role` from purpose, tools, and the squad goal's `Out of scope` — **no new question is added to the flow**. Each bullet carries exactly one of two verbs: `needs:` is a precondition (`squad-spawn`'s dispatch triage probes what it can, informationally — it never gates), `stop:` is a mid-run bound the role **self-polices**; nothing external monitors it, and the docs say so. A fired `stop:` bound ends the run with `status: escalated` and `fired: <the bullet, verbatim>` on the engagement record, plus three hand-back sections — `## What happened`, `## State of the work`, `## What would unblock`. *Stopping well is a deliverable.*

  **An open escalation blocks a `met` verdict**, and only the human's recorded ruling closes one. `verify.sh` computes `escalations_open` mechanically, as a set difference over two inputs neither of which a role controls: the `status: escalated` records, minus the roles named in `.squad/verification.md`'s `resolved_escalations`. A NEEDS-HUMAN row or an open escalation converts to PASS only against a stated what-you-checked / what-you-found, recorded verbatim with attribution and date and marked `PASS (attested)` — permanently distinct from machine-verified truth. A bare assertion earns exactly one push-back, then goes on the record anyway: **the human is never blocked, they are put on the record.** This is the first rule in the repo's history that binds the human rather than the squad.

  **The load-bearing invariant: a role can never mint the human's ruling.** The engagement record's status enum stops at `active | amended | escalated` — there is no `resolved` status and no `resolution:` field anywhere a role writes, on any dispatch path. Stated honestly and not papered over: a role *can* flip its own `escalated` back to `active`, which is behaviorally identical to never having stopped — the acknowledged aspirational half of #14. What it cannot do is manufacture the ruling.

  Numbering is append-only: **#12 was deliberately left unused** when these two shipped, and documented nowhere as existing. It is filled in this same release — see "Hard rule #12" below.

- **Hard rule #13 — a belief with no source is a rumor. The shared world model.** `goal.md` is a shared *task* representation; there was no shared *domain* representation. Roles rediscovered the same facts and — worse — could hold silently contradictory beliefs with nothing in the system able to notice. Now every role has a belief ledger at `.squad/world/claims-<role>.md`, granted **positionally** from its own `agent_type` exactly as its engagement record and hand-off outbox are. Each belief carries `Claim`, `Source`, `Grade`, `Observed` — `Grade` reusing hard rule #11's four evidence classes, one vocabulary across the plugin, never a number.

  **The guarantee is a parser, not a request.** A block missing any required field, or carrying an off-vocabulary `Grade`, is invalid: it is counted, named with what it is missing, and **excluded from every projection — it never reaches a prompt**. `skills/squad-world/scripts/world.sh` is that parser (read-only, jq/awk, JSON lines — `verify.sh`'s established pattern). Asking roles in prose to source their claims would have been the aspirational half only; this rule has no aspirational half.

  **`disputed` is derived, never writable.** Two `live` blocks under one key from *different* owners **are** the dispute — no one writes the word, and nothing resolves it. Not averaged, not latest-wins, not by owner priority. The human adjudicates by hand in `claims-user.md`, and the losing block is edited to `Status: superseded` **in place, never deleted**, so the ledger records who thought what and when they found out otherwise.

  **Ownership cannot be forged, including by a role named `user`.** The `PermissionRequest` hook derives the grant and refuses the reserved owner names `user` and `research` unconditionally — otherwise a role merely *named* `user` would be handed the file the human's rulings live in and could mint the adjudication that settles a contested belief. Role names come from a hand-edited roster; nothing else would have caught it.

  **The projection is bounded by the script, not by hope.** `world.sh --index` performs the projection itself — capped (default 50), 80-**byte**-truncated recency-ordered lines (a byte cap so it is identical at every locale, and the cut never splits a UTF-8 character), full untruncated blocks for up to 5 disputed keys, explicit `+N more on disk` / `+K more disputed` tails, and the invalid count on its own line. `squad-spawn` and the workflow dispatch template bake that stdout **verbatim**; neither reformats it. A disagreement is never summarized to one line, because a one-line summary is how a disagreement gets missed.

  **Conflicts route, they do not gate.** `verify.sh` re-derives `world_conflicts` itself and `squad-verify` reports it — but unlike `escalations_open` (#14) it never blocks a `met` verdict. #13 is a shared domain representation, not a declared bound.

  Committed and **never cleared on dispatch** — accumulating is the point — and parked/restored wholesale with the squad by `squad-goal`, which never merges two squads' ledgers. `spawn.sh collect` brings a worktree-isolated role's claims file back alongside its engagement record. Stated as non-goals, not omissions: **no TTL**, **no semantic contradiction detection** (only identically keyed live blocks are ever compared — two roles can contradict each other in different words and nothing notices), **no auto-resolution ever**, **no cross-squad merge**, and grades that are **self-reported** — nothing can verify a `Source:` line tells the truth.

- **Hard rule #12 — told, not inferred. The partner model.** The plugin had **zero** representation of the human operating it: every role treated every human identically — same explanation depth, same things settled silently, same things surfaced. This is the last of the paper's four desiderata (§2.3 desideratum 1, *"You understand me"*) and the only one that had no mechanism at all. It now has one artifact, `.squad/partner.md`, and a ninth skill, `squad-partner`, that is its **only writer anywhere in the plugin**.

  **The name is the mechanism.** `.squad/partner.md` contains only statements the human confirmed **in the same turn they were written** — `create` prints the final body verbatim and writes only what the human affirms in that reply; `update` diffs before it writes; `delete` requires the literal phrase `yes, delete`. Nothing in the plugin observes, infers, or accumulates a fact about the human into it: not from how they have been working, not from a pattern across turns, not from a mid-run contradiction. When a run visibly contradicts the file, `squad-spawn`'s synthesis **suggests `squad-partner update`** and never writes — a partner model assembled by inference is a dossier; this one is a brief the human dictates.

  **Three sections, each earning its place by changing what a role does.** *Decide vs. ask* changes what gets surfaced instead of silently settled (and carries the attention lines — "batch questions, one block per session" — plus a deadline tie-break). *Standing constraints* bind every squad in the project the way `goal.md` binds one squad; `squad-onboard` pre-populates a new goal's Out of scope from them, and `squad-role` turns "always ask first" items into `stop:` bullets (never `needs:` — an ask-first item is a mid-run bound, not a precondition), sparingly: a promoted item **ends the run** under #14, while every other ask-first item a role hits is surfaced with the rest of the work carried on. *Beliefs to check* turns the human's own assumptions into work: a role that touches one reports **confirmed / contradicted / could not test**. Two sections were cut on purpose and are documented as cut — `Expertise` (self-graded, never checked against a consequence) and a standalone `Attention budget` (over-structure; its two load-bearing lines live inside Decide vs. ask).

  **Privacy is a default offer, not a mechanism, and the docs say so in those words.** This is a model of a person living in a git repo, and §5.3 of the source paper flags such models as dual-use. `create` proposes the file write and the project's `.gitignore` line as **one write set**: accepting the default keeps it out of git, declining the ignore half is an explicit, informed opt-in to committing it. Nothing enforces either outcome, and no document in this repo says the file "is private."

  **The hook needed no change — and that was verified by running it, not by reading it.** `.squad/partner.md` fell under the `.squad/` structural reservation the moment it shipped (v0.4.1), so a `**`-scoped role, the `./` and `//` spellings, an absolute path, the in-sandbox Bash surface (`cp`/`touch`/`ln`/`mkdir`), a main-session call carrying no `agent_type`, and a role literally *named* `partner` all defer to the human today, with controls proving the same hook still auto-approves ordinary in-scope writes. **Zero lines changed in `hooks/permission-request.sh`.**

  **Two read channels, one absence contract.** `session-start.sh` appends the file immediately after the goal — the goal always comes first — behind a bare `[ -s ]` gate; `squad-spawn` and `templates/squad-dispatch.workflow.js` **bake** the full body plus a binding block into every spawn prompt (hard rule #4), because the gitignored-by-default file is typically absent inside a worktree. No file, or an empty one, means byte-identical `SessionStart` output, byte-identical spawn prompts, and a byte-identical `verification.md` — pinned by 8 new `tests/session-start.bats` cases plus 4 in `tests/spawn.bats` that render the workflow template's prompt for real (a `node --check` proves the file parses, never that `args.partner` reaches a role), and confirmed by diffing this build's `SessionStart` output, workflow spawn prompt, and `verify.sh` output against `main`'s. On the workflow path, where every agent runs under `acceptEdits` and the reservation is inert, the prompt states out loud that no role may write the file.

  **The partnership receipt completes.** `squad-spawn`'s closing counter — `N [assumed] bullets quoted, K blocking a PASS · N escalations · N ask-first decisions surfaced instead of auto-decided` — no longer carries a placeholder for a system that doesn't exist. It is still emitted only when at least one count is non-zero. Stated as limits, not omissions: **no CI lint** for a file no machine parses (the roster lint guards a hook; this would guard nothing), **nothing verifies currency** — no statement in the file expires until a role checks it or the human runs `update` — and **completeness is bounded by what the human chose to say**, since `create` asks at most three skippable questions on purpose. `squad-onboard`'s **one mandatory question stays one**: the partner-model offer rides the closing message and is skipped entirely when a file already exists.

- **Guided domain research — the squad looks before it guesses.** `squad-onboard` went goal → decompose → propose roles, and the middle step ran entirely on model priors. For an unfamiliar tool, a specific brand, a niche regulation, a bespoke codebase, or anything past the training cutoff, the decomposition was a guess wearing a decomposition's costume — and nothing downstream caught it, because `squad-verify` checks the goal's Definition of done, never whether the *workstreams* were the right ones. There is now an optional pass of real domain research between the two, behind two human gates.

  **It ships as a fifth verb on `squad-world`, not a skill of its own** — the criterion `CONTRIBUTING.md` states is *a new skill only when the human authors the artifact*, and a finding's content originates in the world (a URL, a tool read, a file); the human *gates* it, and gating is not authorship. Research added **zero** skills. **Zero new files, zero new templates, zero new hard rules** — the same `.squad/world/claims-<owner>.md` schema, in the same ledger, read by the same parser.

  **Both gates are the human's, and neither is a rubber stamp.** Gate 1 is the plan: 3–6 questions derived from the goal just confirmed, each shown with the source class that would answer it and a visibly absent class annotated inline, cost printed at the offer. Gate 2 is the findings, shown as **full belief blocks** — the human ratifies exact text, not a summary — and one reply may rewrite a claim, downgrade a grade, drop a finding, answer an open question, or discard everything. Upgrading *to* `confirmed` is refused unless the human supplies the proving locator: the glossary binds them too. Skipping either is one word, and a squad that skips is byte-identical to one running a version of the plugin that never shipped this.

  **Rule #13 under its heaviest load, made structural.** `claims-research.md` is the single most tempting place in this plugin to write an ungrounded claim, so `world.sh` now carries a **per-owner grade ceiling**: a block there graded `inferred` or `assumed` is invalid, reason `research_grade_ceiling` — deliberately distinct from `bad_grade`, because the grade is on-vocabulary and simply too weak for this one owner. Research may assert only `confirmed` or `reported`. This is the one deliberate research fingerprint in shipped script code, chosen over a sentence in a skill body, because guarding the plugin's most tempting rumor path with an instruction is exactly what this repo says it does not do. `claims-user.md` has no ceiling and never will — the human may assert an inference; it is their prerogative and their name is on it.

  **A contradiction with the goal stops the run** (R2). Four triggers, all against text *quoted from* `.squad/goal.md`: a Definition-of-done signal made already-true, impossible, or unmeasurable; a falsified premise in the outcome; something the goal lists as Out of scope; a deadline or quality bar shown unachievable as written. It does not fire on merely-harder, and **no quoted goal line means no stop**. When it fires it is the only thing on screen and Gate 2 is unreachable until ruled — amend (through `squad-goal`, never automatically: hard rule #1 makes the goal binding), reject with the ruling recorded, proceed on the record, or stop. **Labelled honestly as an instruction, not a mechanism** — nothing enforces it but the skill body.

  **Findings change the team, or the docs say they didn't.** Citations alone are decoration, so three mechanisms close the loop: **rewrite rules** (*already exists* removes a workstream · *changed or broke* inserts a precursor · a *weight* finding reorders), **the delta line** printed at the decomposition confirm the human already gives, with uncited workstreams marked `(from priors)` — and, in `squad-role`, **belief-derived bounds**: a `confirmed` finding that constrains a role becomes a binding `stop:` bullet citing its belief key (#14), and a question research came back **unanswered** on becomes a `needs:` bullet that `squad-spawn`'s triage surfaces to the human as `starts: YOU` rather than swallowing as non-checkable. A `reported` finding earns no bound — the human downgraded it precisely because it wasn't strong enough to bind.

  **Four source classes, each degrading independently and honestly:** no network ⇒ the question is **skipped**, never guessed · no connector ⇒ **unresearchable**, never inferred · a question no available source can answer is **unanswered**, never backfilled with an `inferred` claim wearing a finding's clothes. Fan-out is bounded at ≤4 concurrent. Stated as non-goals: not a general-purpose research agent, no standing monitoring, no research without an approved goal, no autonomous re-run, no crawling beyond the approved plan. And stated as a limit nothing can fix: **research cannot know what it did not think to ask** — unlike `unanswered`, an unasked question leaves no trace to notice it is missing.

  Attended beats go from 6 to 7 when research is skipped and 8 when it is accepted; every available compression is already spent, and `squad-onboard` refuses to add another.

### Fixed

- **The two belief parsers disagreed about what "valid" means, and manufactured a dispute that did not exist.** `verify.sh` re-derives `world_conflicts` independently of `world.sh` — deliberately, so the number is worth having — but it did not apply the new per-owner research grade ceiling. On the same ledger, `world.sh` reported `conflicts: 0` (the research block graded `inferred` is invalid and excluded from existence) while `verify.sh` reported `world_conflicts: 1`, counting that same block as a live claimant. `squad-verify` therefore sent the human to adjudicate a dispute `squad-world` would not show them. `parse_claims_file` now takes the owner as an argument — validity is not owner-independent — and applies the identical rule; five bats cases pin both the ceiling and, just as importantly, its *limits*: a `reported` research block still counts, and `claims-user.md` and an ordinary role's `inferred` block both still count, because neither has a ceiling.

- **`.squad/goal.md` was written too late for anything mechanical to use it.** `squad-onboard` saved the goal at the *end* of its flow, but hard rule #4 bakes that file into every dispatch, the research verb's contradiction stop must quote a line **from the file** (no quoted line, no stop — so an unwritten goal silently disabled the stop outright), the stop's amend option routes to `squad-goal`'s **replace** path, which needs a file to replace, and `squad-role` reads it at preflight. The write now happens at Step 3, as soon as the outcome is confirmed and the mode inferred — a file write, not a question, so the beat count is unchanged.

- **The `.squad/` reservation was defeated by a `./` prefix.** `hooks/permission-request.sh` enforced the reservation with a textual prefix test that recognized exactly one spelling. `./.squad/verification.md`, `.//.squad/…`, and absolute paths containing `/./` or `//` all name the same file as `.squad/verification.md`, but missed the test, fell through to `file_scope`, and were auto-approved for any role scoped `**`. That is the v0.4.1 forgery hole reopened by two characters — and the file it reached is the one the human's ruling lives in, so a role could have cleared its own escalation and unblocked a `met` verdict (hard rules #10, #14). Paths are now normalized before any containment test: `//`, `/./`, and a leading `./` are collapsed; `..` is still never resolved, only rejected.

- **The scaffolding-Bash surface never consulted the reservation at all.** That surface tested operands against the role's `environment.workspace` prefix alone, bypassing `squad_grant`. A roster declaring `workspace: ".squad"` therefore made every reserved path a sandbox path on that surface: `cp forged.md .squad/verification.md`, `ln -f`, and `touch` over `verification.md`, `goal.md`, `roster.json`, and another role's engagement record were all auto-approved — while the *identical* Edit/Write was correctly deferred, as it has been since v0.4.1. `.squad/` operands now take the same `squad_grant` decision on both surfaces. A role's own record, own outbox, and ordinary nested sandboxes are unaffected.

- **A recorded human ruling was silently ignored when written in canonical YAML.** `verify.sh`'s `resolved_escalations` parser required the block-style dash at column 0, so the two-space-indented list that `templates/verification.md` and `examples/klaviyo-audit.md` both document never matched. The subtraction found nothing to subtract, `escalations_open` stayed above zero forever, and `met` became unreachable no matter what the human ruled. Indentation is now accepted; flow style still is too.

- **Four mermaid diagrams had never rendered.** `ARCHITECTURE.md`'s dispatch sequence diagram, the end-to-end sequence diagrams in `LOGIC.md` and `LOGIC.local.md`, and the dispatch hand-off diagram in `docs/workflows-runtime-reference.md` failed to parse on GitHub, for two separate reasons — both found by actually rendering every block rather than reading them:
  - a **`;` inside a sequence message** is a mermaid *statement separator*, so the message truncated mid-sentence and the remainder parsed as a bare statement;
  - **`&lt;`/`&gt;` entities break the sequence parser.** This is the exact opposite of the flowchart rule — in a flowchart node label you *must* escape angle brackets, and this repo had correctly learned that, then applied it one block over where it is a bug.

  `tests/mermaid-lint.sh` now guards both classes in CI. Structural rather than a real render: CI here is shellcheck + bats and finishes in ~25s, and pulling Chromium in would cost minutes for a class of bug this catches for free.

- **`templates/squad-dispatch.workflow.js` was never syntax-checked.** It ships as JavaScript, so a syntax error would have surfaced only at dispatch time. CI now runs `node --check` on it, and shellcheck's glob covers `tests/*.sh` so the new linter lints itself.

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

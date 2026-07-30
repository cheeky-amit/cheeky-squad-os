# Smoke test — cheeky-squad-os end-to-end (v1.0.0)

Copy-pasteable manual verification. Exercises every skill, every hook, and all
five v1.0 hard rules (#11–#15) with one small real goal. The core path (no
optional steps) completes in under 10 minutes on a fresh project; with every
optional step included, budget 20–30.

It does **not** cover negative paths (out-of-scope DEFER, Bash DEFER, fail-open,
`..` traversal, the `.squad/` forgery-hole regressions) — those live in the
automated suite (`tests/permission-request.bats`, `tests/spawn.bats`,
`tests/world.bats`, `tests/verify.bats`, run in CI).

**Optional steps are marked `(OPTIONAL)` in their heading.** Skip any of them
and the rest of the walkthrough still completes — that is itself part of what
each one proves: a squad that skips research, a partner model, or an
escalation looks exactly like one running a version of this plugin that never
shipped the feature.

Some steps ask you to nudge a role's task at dispatch time to manufacture a
real stop-condition firing and a real belief conflict — without that nudge,
those two mechanisms exist but have nothing to react to on a first run. This
is a property of the walkthrough, not a hedge on the mechanism: the resulting
artifacts (`.squad/role-plan-*.md`, `.squad/verification.md`,
`.squad/world/claims-*.md`) are exactly what a real escalation or a real
dispute produces.

---

## Prerequisites

```
claude --version   # need v2.1.32 or later
which jq           # need jq installed (brew install jq / apt-get install jq)
git --version      # any modern git
```

The optional research pass (Step 3) needs no extra service to demonstrate —
on a small local project its questions resolve via the "this codebase and
project files" source class, which is always available.

Create a scratch directory and cd into it:

```
mkdir -p ~/tmp/squad-smoke && cd ~/tmp/squad-smoke
git init -q
echo "# Smoke test project" > README.md
git add . && git commit -q -m "init"
```

---

## Step 0 — squad-partner create (OPTIONAL — hard rule #12)

From a fresh session in `~/tmp/squad-smoke`:

```
/cheeky-squad-os:squad-partner
```

There's no prior conversation to draft from, so expect a near-empty draft and
up to 3 skippable questions. Answer roughly:

- *"Anything you'd rather decide for yourself unless I ask?"* → "small wording tweaks — decide those yourself"
- *"Anything I should always check with you before doing?"* → "touching LICENSE.md or any legal file — always ask first"
- *"Any standing rule that applies to every squad here, not just this one?"* → skip

`squad-partner` prints the **final file body verbatim** and asks you to accept
both the write and the default `.gitignore` line in one turn. Reply `go`.

**Verify:**

```
cat .squad/partner.md
cat .gitignore   # should now list .squad/partner.md, if you accepted the default
```

Should show frontmatter `created`/`updated` (same timestamp) and the three
fixed sections — `## Decide vs. ask`, `## Standing constraints`,
`## Beliefs to check` — containing only what you just typed. `git status`
won't show `.squad/partner.md` if you accepted the ignore line; the file is
still on disk — check it directly, not through git.

**Why this verifies:** every sentence in the file traces to something you
said in this same turn — nothing inferred, nothing carried over. This file
also sets up two later steps: `squad-onboard` will read it silently at Step 3
(and pre-populate the goal's Out of scope from it), and `squad-role` will
turn the "always ask first" item into a role's declared `stop:` bound at
Step 4.

If you skip this step, skip the partner-model-specific checks in the steps
below too — everything else in this walkthrough behaves identically without
it.

---

## Step 1 — Install the plugin

From the directory containing this repo's checkout:

```
/plugin marketplace add /absolute/path/to/cheeky-squad-os
/plugin install cheeky-squad-os@cheeky-squad-os
```

**Verify:**

```
/plugin list
```

Should show `cheeky-squad-os@cheeky-squad-os` as installed. The plugin's
three hooks should be wired (confirm with `/hooks`); all nine skills should
be visible in your skill listing (`squad-onboard`, `squad-goal`,
`squad-role`, `squad-env`, `squad-spawn`, `squad-roster`, `squad-verify`,
`squad-world`, `squad-partner`).

---

## Step 2 — SessionStart hook fires (no goal yet)

Open a fresh Claude Code session in `~/tmp/squad-smoke` and ask:

```
What's our squad goal?
```

**Expected:** Claude responds with something like *"No squad goal set — run
/cheeky-squad-os:squad-onboard."* This text comes from the `SessionStart`
hook injecting `additionalContext`. If Claude says *"I don't know"* or
*"there is no squad"*, the hook didn't fire — check `/hooks` and the plugin
install.

**If you ran Step 0:** the same response should also reflect your partner
model — e.g. a mention of always asking before touching LICENSE.md. The
`SessionStart` hook appends `.squad/partner.md`'s content immediately after
the goal notice whenever the file exists and is non-empty, independent of
whether a goal has been set yet (a project can have a partner model before
it has ever run `squad-onboard`).

**Why this verifies:** the hook ran at session start, read `.squad/goal.md`
(which didn't exist) and, separately, `.squad/partner.md` (which may already
exist from Step 0), and injected both as `additionalContext`. Claude
reproduced them back to you.

---

## Step 3 — squad-onboard with a real goal (research pass OPTIONAL)

In the same session:

```
/cheeky-squad-os:squad-onboard
```

Use this input when asked *"Do you have a goal?"*:

```
audit the README in this project for clarity and rewrite weak sections — within an hour
```

`squad-onboard` should:
- Reformulate as outcome — e.g., *"Deliver a clarity-audited and rewritten README.md with at least 3 specific improvements applied, within one hour."*
- Ask you to confirm. Say yes.
- Infer mode = **One-time** (bounded deliverable, single deadline).

**If you ran Step 0**, in the same message as the mode inference, Claude
should also say it read `.squad/partner.md` silently and pre-populated one
`Out of scope` bullet from your standing constraint — something like *"Never
modify LICENSE.md or other legal files (from `.squad/partner.md`'s standing
constraints)"* — and name where it lands: `.squad/goal.md` is committed,
`.squad/partner.md` is not.

**Research offer — Gate 1 (OPTIONAL):** in the same message, Claude prints a
3–6 question research plan derived from the confirmed outcome, each question
annotated with which source class would answer it. Reply `go` to run it as
written, or `skip` to jump straight to the workstream list below (decompose
from priors, no citations, no delta line — indistinguishable from a run of
this plugin before this feature existed).

If you say `go`: on a small local project, expect most questions to resolve
via **"this codebase and project files"** (always available, no external
connector needed) — e.g. confirming the current README's rough length or
structure. **Gate 2** then shows every finding as a full belief block
(Claim/Source/Grade/Observed), graded `confirmed` or `reported` only. Reply
`go` to accept as written.

**Verify (only if you ran the research pass):**

```
cat .squad/world/claims-research.md
```

Should show one or more `## Belief:` blocks, each `Grade: confirmed` or
`Grade: reported` — never `inferred` or `assumed` (`world.sh`'s per-owner
grade ceiling rejects those from this one file; hard rule #13).

Then the decomposition: Claude prints the (possibly rewritten) workstream
list plus a delta line — either what research changed, or *"Research changed
nothing…"* if it didn't. Confirm. Propose 2 roles — names that fit:
`readme-auditor` and `readme-rewriter`.

**Verify the goal saved:**

```
cat .squad/goal.md
```

Should contain `mode: one-time`, an ISO-8601 `created`, an ISO-8601 `target`
(about an hour from now), the outcome paragraph, and a Definition of done.
If Step 0 ran, `## Out of scope` should include the LICENSE.md bullet
attributed to your partner model.

---

## Step 4 — squad-role generates two roles (Stop conditions derived automatically)

When `squad-role` runs for role 1 (`readme-auditor`), answer roughly. (If
`squad-role` also asks an optional effort question after the model question,
skip it — it inherits the session's effort level, and the rest of this
walkthrough is unaffected.)

- **Q1 purpose:** "Read README.md, identify unclear sentences, weak headings, and missing context; write findings to reports/readme/audit.md."
- **Q2 name:** `readme-auditor`
- **Q3 file_scope:** `README.md, reports/readme/**`
- **Q4 tools:** `Read, Write, Grep`
- **Q5 model:** `sonnet`
- **Q6 isolation:** no (the two roles don't write to overlapping paths)
- **Q7 sandbox:** yes (it gives the auditor a workspace + verifies its tools)

For role 2 (`readme-rewriter`):

- **Q1 purpose:** "Read the auditor's findings and the original README.md; rewrite weak sections inline; write the final README to reports/readme/README.rewritten.md."
- **Q2 name:** `readme-rewriter`
- **Q3 file_scope:** `reports/readme/**`
- **Q4 tools:** `Read, Write, Edit`
- **Q5 model:** `sonnet`
- **Q6 isolation:** no

**No new question, but a new block in the Confirm printout:** after Q7,
`squad-role` derives 2–4 `## Stop conditions` bullets for each role, never
asking about them. Expect at least the floor bullets (hard rule #14), plus,
since the squad goal now excludes LICENSE.md, a `stop:` bullet naming it —
e.g. *"stop: the task would require modifying LICENSE.md — excluded by the
squad goal."* If Step 0 ran, this same bullet (or a sibling one derived
directly from the partner model's "always ask first" item) should be marked
inline `(from .squad/partner.md; .squad/role-goal-readme-rewriter.md is
committed, that file is not)`.

**Verify generated artifacts:**

```
ls -la .claude/agents/
ls -la .squad/
cat .squad/roster.json
cat .squad/role-goal-readme-rewriter.md
```

Should show:
- `.claude/agents/readme-auditor.md` and `.claude/agents/readme-rewriter.md` (both with valid YAML frontmatter — verify with `head -10`)
- `.squad/role-goal-readme-auditor.md` and `.squad/role-goal-readme-rewriter.md`, each with a `## Stop conditions` section — 2–4 bullets, each starting `needs:` or `stop:`, never a bare bullet
- `.squad/roster.json` with both roles, `active: true`
- `.squad/roster.md` (auto-generated human view)
- if you answered yes to Q7, `readme-auditor`'s entry has an `environment` block and `.squad/workspaces/readme-auditor/**` is in its `file_scope`

---

## Step 4.5 — squad-env provisions the sandbox (OPTIONAL)

If a role got a sandbox in Step 4:

```
/cheeky-squad-os:squad-env
```

`squad-env` should materialize the sandbox and report any uncontainable needs:

```
ls -la .squad/workspaces/readme-auditor/      # bin/, env, scaffolded dirs
cat  .squad/workspaces/readme-auditor/env     # PATH + vars, sourced not exported
```

Should show the workspace dir with `bin/`, a sourced `env` file, and the
scaffolded subdirs. Any missing system tool / MCP server is surfaced as a
`global_need` for you to approve — not installed automatically.

---

## Step 5 — squad-spawn dispatches the squad (engagement record, world index, partner model all baked)

In the same session:

```
/cheeky-squad-os:squad-spawn
```

**To manufacture a real escalation and a real belief conflict for Steps 7
and 9 below (OPTIONAL — skip this paragraph for a clean run with neither),**
add this in the same message:

> When you dispatch readme-rewriter, after it finishes the README rewrite,
> also ask it to check whether LICENSE.md's copyright year needs bumping.
> Also ask readme-auditor, once it has read README.md, to record a belief
> under exactly the key `readme-tone` describing the README's current tone,
> graded `confirmed`, sourced from having read the file.

`squad-spawn` should, at preflight:
- Read `.squad/goal.md`, see `mode: one-time`.
- Read `.squad/roster.json`, find both roles.
- **Compute the shared world model index once (hard rule #13).** If Step 3's
  research ran (or any belief already exists), `world.sh --index`'s output
  gets baked into every role's prompt this dispatch. You can see what it
  would print directly:
  ```
  bash /path/to/cheeky-squad-os/skills/squad-world/scripts/world.sh --index
  ```
  Run from `~/tmp/squad-smoke` — the script resolves `.squad/world/`
  project-relative. If `.squad/world/` doesn't exist yet and no research
  ran, this prints nothing — correctly: the "Shared world model" section is
  omitted from every prompt this dispatch, never printed empty.
- **Read the partner model once (hard rule #12).** If Step 0 ran, its full
  text is baked verbatim into every role's prompt, positioned right after
  the goal — not re-read by the role mid-run.
- **Dispatch triage.** One line per role: `starts: machine — <role>` if
  every checkable `needs:` bullet passed (expected here, since nothing
  you've set up should fail one), or `starts: YOU — <role>: <reason>` if
  one didn't.

Dispatch `readme-auditor` via the Agent tool first. The spawn prompt **must**
contain the full text of `.squad/goal.md` and
`.squad/role-goal-readme-auditor.md` (hard rule #4) — the SessionStart hook
does not fire for subagents, so prompt-baking is the only context channel.

**Step 0 of the role's own contract (hard rule #11):** before its first
other write, `readme-auditor` must publish
`.squad/role-plan-readme-auditor.md`. Check it during or right after the
run:

```
cat .squad/role-plan-readme-auditor.md
```

Should show frontmatter `role: readme-auditor`, `status: active`, and body
sections `## Task read`, `## Intended approach`, `## Deliverables`,
`## Assumptions` — each assumption bullet graded exactly one of
`[confirmed]`/`[reported]`/`[inferred]`/`[assumed]`, and every `[assumed]`
bullet carrying an `if wrong → <deliverable or DoD signal>` clause.

After `readme-auditor` finishes (writes `reports/readme/audit.md`), dispatch
`readme-rewriter` with the same prompt-baking pattern, plus the LICENSE nudge
above if you added it.

---

## Step 6 — Verify the goal, world model, and belief-writing duty reached the subagents

```
ls -la reports/readme/
cat reports/readme/audit.md
```

The audit file should exist and its content should reference the **squad
goal text** — phrases like "as required by the squad goal", "the goal calls
for at least 3 specific improvements", or some other evidence the subagent
saw the goal. If the audit reads like a generic README review with no
awareness of the goal, **the prompt-baking failed** — this is a regression.

Then:

```
cat reports/readme/README.rewritten.md
```

The rewritten README should exist, address the auditor's specific findings,
and be at least as long as the original.

**If you added the `readme-tone` nudge in Step 5:**

```
cat .squad/world/claims-readme-auditor.md
```

Should show a `## Belief: readme-tone` block: `Claim` describing the
README's tone, `Source` pointing at having read `README.md`,
`Grade: confirmed`, an ISO-8601 `Observed` date, `Status: live`.

---

## Step 7 — Verify the escalation, if you triggered one (hard rule #14)

**Only if you added the LICENSE nudge in Step 5** — otherwise skip this step
entirely; `.squad/role-plan-readme-rewriter.md` should show `status: active`
with no escalation sections, and that absence is itself the expected result
of not asking the role to touch its declared bound.

```
cat .squad/role-plan-readme-rewriter.md
```

Expected: frontmatter `status: escalated`, `fired: <the LICENSE stop-condition
bullet from Step 4, verbatim>`, plus three sections at the end of the file —
`## What happened`, `## State of the work`, `## What would unblock`. The
`## Deliverables` list should still show the README rewrite as complete —
per the role's stop-condition contract, it leaves in place whatever it had
already finished before the bound fired; only the LICENSE-check piece is
left undone. Nowhere in the file should you find a `resolved` status or a
`resolution:` field — that schema has neither, on purpose (hard rule #14):
a role can open an escalation but never close one.

---

## Step 8 — squad-verify decides, with attestation (hard rules #10, #15)

In the same session:

```
/cheeky-squad-os:squad-verify
```

`squad-verify` should:
- Run `skills/squad-verify/scripts/verify.sh` (JSON-lines evidence scaffold).
- If Step 7's escalation fired, the summary line carries
  `"escalations_open": 1` — this gates the verdict below `met` regardless of
  what every individual signal shows (hard rule #14, "an open escalation
  blocks a `met` verdict, full stop").
- Judge each Definition-of-done signal PASS / FAIL / NEEDS-HUMAN with
  concrete evidence — never a guess.

**Attestation (Step 5.5, hard rule #15) — "zero ritual when nothing is
wrong":** it fires only if at least one signal is NEEDS-HUMAN or at least one
escalation is open. If both this run's signals machine-PASSed and Step 7's
escalation never fired, this step is skipped entirely — print nothing, ask
nothing, go straight to writing the file.

Otherwise, expect prompts like:

> *"The `readme-rewriter` escalation — fired: `<bullet>` — is still open. What's your ruling?"*

Answer with a concrete ruling, e.g.: *"Checked LICENSE.md — the copyright
year is already current, no change needed. Drop this deliverable."* This
gets recorded **verbatim**, with your name/handle and today's date, and
closes the escalation (`readme-rewriter` is added to `resolved_escalations`).

> *"Signal `<a judgment-based DoD bullet, e.g. 'at least 3 specific improvements applied'>` is NEEDS-HUMAN. Can you attest to it?"*

Answer with what you actually checked, e.g.: *"I read the rewritten
README — it fixes the vague intro, adds a quickstart section, and clarifies
the license line. That's 3 specific improvements."* Recorded as
`PASS (attested)` — permanently distinct from a machine-verified `PASS`.

**Optional micro-test of the push-back rule:** reply to either prompt with a
bare assertion first — *"looks good"* — and confirm you get pushed back on
**exactly once**: *"I need what you checked and what you found, not just an
assertion."* Then give the real answer above (or repeat the bare assertion —
it still gets recorded, with a `Notes:` line saying no supporting detail was
given; the human is never blocked twice).

**Verify:**

```
cat .squad/verification.md
```

Should show, in this order: any FAIL signals, then NEEDS-HUMAN signals
(including anything you attested, tagged `PASS (attested)`), then
machine-verified PASS signals; a role-deliverables table; a `## Process`
section (engagement-record evidence, present because at least one role
published a record this run); a `## Escalations` section if Step 7 fired
one, showing your `Ruling:` verbatim with attribution and date; and a
`## Verdict` paragraph last. Frontmatter should show `escalations_open: 0`
and `resolved_escalations` listing `readme-rewriter` if you ruled it, and
`world_conflicts` present (even as `0`) once `.squad/world/` exists at all —
the verdict itself, not the summary from Step 6, is the authority on whether
the goal is met (hard rule #10).

---

## Step 9 — squad-world adjudicate (OPTIONAL — needs the `readme-tone` nudge from Step 5)

Seed a conflicting belief as yourself:

```
/cheeky-squad-os:squad-world
```

Say something like: *"The README's tone should read friendlier and more
conversational — note that for the record."* When `squad-world`'s **seed**
flow proposes a key, override it to the exact key `readme-tone` (matching
what you asked `readme-auditor` to use in Step 5, so the two collide).
Grade: `assumed` — it's your opinion, not something you checked.

**Expected:** `seed` runs its collision check against every owner's claims
file before writing, finds `readme-auditor`'s live `readme-tone` block
under a **different** owner, and refuses to silently add a second live
block under the contested key — it should say so and offer **adjudicate**
instead.

Accept: *"adjudicate readme-tone."*

**Expected:** both sides shown in full — owner, claim, source, grade,
observed — neither summarized thinner than the other. `squad-world` asks
for your ruling; it never proposes one for you to rubber-stamp. Give one,
e.g.: *"Keep it technical for the audit sections, friendlier for the
intro — that's the new claim."* Confirm the write to `claims-user.md`.
`squad-world` should then ask, **per losing block, with an explicit yes
before writing**, whether to mark `readme-auditor`'s original block
`superseded`. Say yes.

**Verify:**

```
cat .squad/world/claims-user.md            # your ruling, live, Source names the adjudication
cat .squad/world/claims-readme-auditor.md  # the original block — Status: superseded, still on disk, never deleted
```

Re-run `/cheeky-squad-os:squad-world` and ask to inspect. The `readme-tone`
key should no longer appear under "Disputed keys" — only one `live` block
remains, under `claims-user.md` — and the run's summary `conflicts` count
should read `0`.

---

## Step 10 — Verify the PermissionRequest hook auto-approved in scope

Inspect the session transcript. During Step 5, when `readme-auditor` wrote
to `reports/readme/audit.md`, there should have been **no user permission
prompt** — the `PermissionRequest` hook auto-approved because
`reports/readme/**` is in the role's `file_scope`. Same for
`readme-rewriter` writing to `reports/readme/README.rewritten.md`, and for
either role publishing its own `.squad/role-plan-<role>.md` and
`.squad/world/claims-<role>.md` — those two are granted structurally, derived
from the role's own `agent_type`, never from `file_scope` (the `.squad/`
structural reservation).

If you saw prompts during those writes, the hook isn't matching scopes
correctly — check `hooks/permission-request.sh` output by piping synthetic
input through it manually:

```
echo '{"agent_type":"readme-auditor","tool_name":"Write","tool_input":{"file_path":"'$(pwd)'/reports/readme/audit.md"}}' \
  | /path/to/cheeky-squad-os/hooks/permission-request.sh
```

Should print a JSON allow decision. If it prints nothing, the hook is
deferring — check the plan gate first (`.squad/role-plan-readme-auditor.md`
must exist, hard rule #11), then the roster lookup and the glob match.

---

## Step 11 — Verify SessionStart fires with a goal present

Open a **fresh** Claude Code session in `~/tmp/squad-smoke`:

```
exit   # leave the current session
claude # start a new one in the same directory
```

Then ask:

```
What's our squad goal?
```

**Expected:** Claude responds with the full contents of `.squad/goal.md` —
outcome paragraph, Definition of done, Out of scope. The user didn't tell
Claude this. The `SessionStart` hook injected `.squad/goal.md` as
`additionalContext` automatically, immediately followed by
`.squad/partner.md`'s content if Step 0 ran and the file is still present
and non-empty.

**If Step 7's escalation is still open** (you skipped or declined to rule
on it in Step 8): the same response should end with a line like
*"1 open escalation is waiting on your ruling — see
`.squad/verification.md`"* — the `SessionStart` hook's own read of
`status: escalated` records minus `.squad/verification.md`'s
`resolved_escalations`. If you ruled on it in Step 8, this line should be
absent.

If Claude says *"there is no goal"* or refers you to a file, the hook isn't
injecting properly.

---

## Pass criteria

All of these must be true (skip a row if you skipped its step):

- [ ] Step 0 (optional): `.squad/partner.md` contains only what you typed this turn
- [ ] Step 2: Claude reproduced the "no goal set" notice, plus your partner model if Step 0 ran, without you mentioning either file
- [ ] Step 3: `.squad/goal.md` exists with valid frontmatter; if research ran, `.squad/world/claims-research.md` holds only `confirmed`/`reported` blocks
- [ ] Step 4: `.claude/agents/*.md` and `.squad/roster.json` populated correctly; each role-goal's `## Stop conditions` has 2–4 `needs:`/`stop:` bullets, never a bare one
- [ ] Step 4.5 (optional): `.squad/workspaces/readme-auditor/` materialized with `bin/`, `env`, scaffolded dirs
- [ ] Step 5: `squad-spawn` ran without errors; each dispatched role published `.squad/role-plan-<role>.md` before any other write
- [ ] Step 6: `reports/readme/audit.md` references the squad goal text (proof of prompt-baking); if nudged, `claims-readme-auditor.md` holds the `readme-tone` belief
- [ ] Step 7 (conditional on the nudge): `.squad/role-plan-readme-rewriter.md` shows `status: escalated`, `fired:`, and the three hand-back sections — with no `resolved`/`resolution:` field anywhere
- [ ] Step 8: `.squad/verification.md` exists with per-signal evidence, an `## Escalations` section if one fired, and a met/partial/unmet verdict; any attestation is tagged `PASS (attested)` or recorded as a `Ruling:`, never merged into a plain `PASS`
- [ ] Step 9 (optional): the `readme-tone` conflict is resolved — one `live` block in `claims-user.md`, the other `superseded` in place, `world.sh` reports `conflicts: 0`
- [ ] Step 10: No permission prompts for in-scope writes
- [ ] Step 11: A fresh session knows the goal (and partner model, and any open-escalation notice) without being told

If all of these pass (accounting for whichever optional steps you ran), the
plugin's v1.0 surface is exercised end-to-end. Negative-path coverage
(out-of-scope DEFER, Bash DEFER, no-jq fail-open, `..` traversal, the
`.squad/` forgery-hole regressions) is in the automated suite — see
`tests/permission-request.bats`, `tests/spawn.bats`, `tests/world.bats`, and
`tests/verify.bats`.

---

## Cleanup

```
rm -rf ~/tmp/squad-smoke
/plugin uninstall cheeky-squad-os@cheeky-squad-os   # optional; leaves plugin available
```

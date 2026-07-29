---
name: squad-verify
description: Use when the user wants to know whether the squad's work is actually done — phrases like "verify the squad", "is the work done", "check the definition of done", "did we hit the goal", "verify deliverables", "are we finished". Also invoked by squad-spawn at the end of its per-spawn synthesis. Checks every Definition-of-done signal in .squad/goal.md against read-only evidence, checks each active role's deliverables landed in its file_scope, and writes .squad/verification.md with a met/partial/unmet verdict. This skill writes .squad/verification.md only; it never modifies goal.md or roster.json, and it never re-dispatches workers.
version: 0.1.0
author: cheeky-squad-os
license: MIT
allowed-tools: [Read, Write, Bash]
compatible-with: [claude-code, agentskills-1.0]
---

# squad-verify

You are the squad's supervisor. **Synthesis summarizes; verification decides.** `squad-spawn`'s synthesis reports what each role produced — your job is the other half: deciding whether the goal's **Definition of done** is actually satisfied, with evidence, and recording the verdict where every future session can see it.

Three principles bind every step:

1. **Evidence or NEEDS-HUMAN — never guess.** A signal is PASS only when you can point at the file, command output, or value that proves it. Anything you cannot mechanically check goes to NEEDS-HUMAN, untouched.
2. **Read-only judging.** You read files and run read-only checks. You never fix, re-run, or touch deliverables — re-dispatch is `squad-spawn`'s job.
3. **One artifact of record (hard rule #10).** A role cannot write its own verdict. The verdict lives in `.squad/verification.md`. You write that file and nothing else — ever. Engagement records (below) are read as process evidence; they are never edited by this skill.

## Preflight — refuse if not ready

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."* and stop.
2. Read `.squad/roster.json`. If absent or `roles` is empty: refuse with *"Roster is empty. Run `/cheeky-squad-os:squad-role` to generate at least one role."* and stop.
3. Note the goal's `mode` from frontmatter (recorded in the verdict; Evergreen squads verify the latest iteration).
4. **Note uncollected worktree records — do not collect them yourself.** A role dispatched under `isolation: worktree` (hard rule #7) wrote its engagement record inside its worktree, where the project root — and so Step 2 below — cannot see it. Collecting is `squad-spawn`'s job (its synthesis runs `spawn.sh collect`), not yours: principle 3 above means you write `.squad/verification.md` and nothing else, and `collect` writes files. If any active role sets `isolation: worktree` and `.squad/role-plan-<name>.md` is absent at the root, say so in that role's `## Process` row — *"record not collected; run `/cheeky-squad-os:squad-spawn` synthesis (or `spawn.sh collect`) and re-verify"* — and judge it as "no record available", never as "the role declined to declare".

## Step 1 — Run the evidence scaffold

From the **project root** (file_scope globs are project-relative), run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/squad-verify/scripts/verify.sh" .squad/roster.json .squad/goal.md
```

It emits one JSON object per line:

- `{"signal": "<text>", "status": "unverified"}` — one per Definition-of-done bullet
- `{"role": "<name>", "scope": […], "files_found": N, "role_goal_present": bool}` — one per active role (carries additional engagement-record fields when one exists — see Step 2)
- `{"summary": true, "roles": N, "signals": N, "errors": K}` — final line

If the script exits non-zero, surface its stderr to the user verbatim (it names the missing prerequisite — usually `jq`, the goal, or the roster) and stop.

## Step 2 — Read the engagement records (process evidence, hard rule #11)

`verify.sh` adds six keys to a role's per-role line, but only for a role that has published `.squad/role-plan-<name>.md` — omitted **entirely**, not `false`/`0`/`null`, when it hasn't (the absence contract: a project with no records produces the same keys as a pre-#11 run — the one deliberate value change is `files_found`, see Step 4):

- `role_plan_present` — always `true` when present at all; the key's absence is what "no record" looks like, never a `false`.
- `role_plan_status` — the record's frontmatter `status` (`active` | `amended`).
- `role_plan_frontmatter_role_match` — `false` if the record's frontmatter `role:` disagrees with the filename. The filename still wins (per `templates/role-plan.md`), but a mismatch is a squad-authoring defect — `verify.sh` has already folded it into the run's `errors` count, and this skill flags it too (Step 4).
- `role_plan_assumption_grades` — `{"confirmed": N, "reported": N, "inferred": N, "assumed": N}`, one count per evidence grade across the record's `## Assumptions`.
- `role_plan_deliverables_missing` — a **count** of `## Deliverables` bullets whose backtick-quoted path isn't on disk. It's a count, not the paths — `Read` the record's `## Deliverables` section directly for which ones.
- `role_plan_assumed_risks` — an array of the `if wrong → …` **target text only**, one per `[assumed]` bullet — not the claim. To quote a full bullet (claim + clause) you must `Read` the record's `## Assumptions` section directly; the array only tells you a match is worth checking for.

Build the process table from these: role · record published (yes/no) · `role_plan_status` · the four grade counts · `role_plan_deliverables_missing` · how many entries in `role_plan_assumed_risks`. A role with no record at all is not automatically a failure — Step 0 is a hook gate on the role's *other* writes, not a content requirement this skill enforces — but say so plainly in its row: without a record there is no process evidence for that role's workstream, only whatever artifact evidence Step 4 finds.

**The forcing rule.** For every dispatched role with a record, treat each entry in `role_plan_assumed_risks` as a candidate target. If a Definition-of-done signal names, or is only supported by, one of those targets, it **cannot PASS on the strength of that same role's own output** — cap it at NEEDS-HUMAN in Step 3. When you cap a signal this way, `Read` that role's record's `## Assumptions` section to find and quote the matching `[assumed]` bullet **verbatim** — claim and `if wrong → …` clause together — as the evidence. `role_plan_assumed_risks` only tells you a match exists; it is not itself the quote. A role's own guess cannot certify itself by producing the very artifact the guess was about — that is what "if wrong" was warning you against.

## Step 3 — Judge each signal

For **each** signal line, first check it against Step 2's forcing rule: if this signal names, or is only supported by, an entry in any dispatched role's `role_plan_assumed_risks`, the ceiling is **NEEDS-HUMAN** — quote the matching `[assumed]` bullet verbatim, read from the record (the target string alone is not the quote), and move on. Otherwise gather evidence with read-only tools and assign exactly one status:

| Status | When | Evidence you must record |
| --- | --- | --- |
| **PASS** | The signal is observably true right now | The file path you read, or the command + output that proves it |
| **FAIL** | The signal is observably false, or the artifact it names is missing | What you looked for and what you found instead |
| **NEEDS-HUMAN** | Not mechanically checkable from this machine (judgment calls, external systems, live metrics you can't query — or capped there by the forcing rule above) | One line on what a human must check, and how (or the `[assumed]` bullet, quoted verbatim, for a forcing-rule cap) |

How to gather evidence:

- If the signal names a **file or artifact** ("report exists at…", "all findings documented in…") — `Read` it. Existing and non-empty with the expected content shape → PASS.
- If the signal names a **countable or runnable check** ("all tests pass", "≥ N entries", "lint is clean") — run the read-only command it implies via Bash and quote the relevant output.
- If the signal names an **external or judgment-based measure** ("converts at >5%", "stakeholder approves", "Lighthouse ≥ 90" when you can't run Lighthouse) — NEEDS-HUMAN. Do not infer it from proxies.

Never average, round, or stretch. A signal that is 90% true is FAIL (or NEEDS-HUMAN if the last 10% isn't checkable) — the goal schema demands signals "checkable without judgement calls", and you are the check.

## Step 4 — Check role deliverables

From the per-role lines, build the deliverables table: role, scope, `files_found`, `role_goal_present`. Note first: `files_found` never counts anything under `.squad/` (`verify.sh` excludes it, mirroring the hook's own reservation) — a role that only ever wrote its engagement record will show `files_found: 0` for that reason alone, so check `role_plan_present` and the record's own `## Deliverables` before reading a zero as "produced nothing." Then:

- A role with `files_found: 0` **and** no engagement record (or a record with an empty `## Deliverables`) produced **nothing inside its scope** — flag it prominently; its workstream is almost certainly the cause of any FAIL.
- A role with `role_goal_present: false` was dispatched without its contract — flag it; the squad's decomposition has drifted from the roster.
- A role with `role_plan_frontmatter_role_match: false` published a record whose own `role:` field disagrees with the filename — flag it; the filename still wins, but this is a squad-authoring defect already counted in `verify.sh`'s `errors`.
- Cross-check each role-goal's **Owned outputs** section (read `.squad/role-goal-<name>.md`): named artifacts that don't exist are FAIL evidence for whichever signal they serve.
- Where `role_plan_deliverables_missing` is nonzero, `Read` that role's record's `## Deliverables` section to find which declared path(s) are missing, and treat each as corroborating FAIL evidence for whichever signal it serves — on top of, not instead of, the role-goal check above.

## Step 5 — Compute the verdict

| Verdict | Condition |
| --- | --- |
| `met` | Every signal is PASS |
| `partial` | At least one PASS, and at least one FAIL or NEEDS-HUMAN |
| `unmet` | No signal is PASS |

Zero parseable signals (the script reported `"signals": 0`) → verdict `unmet`, with one explanatory row: *"goal has no parseable Definition of done — run `/cheeky-squad-os:squad-goal` to add observable signals"*. Never invent signals to judge.

## Step 6 — Write `.squad/verification.md`

Write the file using the schema in `templates/verification.md`:

- Frontmatter: `verdict` (met|partial|unmet), `verified_at` (current UTC, ISO-8601), `goal_mode`, `signals_pass`, `signals_fail`, `signals_human` (counts). No frontmatter field is added for the process feature.
- Body: one `## Signal: <text>` section per signal with **Status / Evidence / Notes**, the `## Role deliverables` table, and a closing `## Verdict` paragraph in plain language.
- `## Process` — conditional on the **engagement**, not per-role: render it only if at least one active role published an engagement record; omit it entirely, not as an empty heading, when none did (the absence contract — byte-identical to a pre-#11 run). When rendered, one row per active role, in roster order — `Role | Record (yes/no) | Status | Confirmed | Reported | Inferred | Assumed | Deliverables declared → delivered`. A role with no record still gets a row (`Record: no`, the rest `—`) — that a role acted with no declared intent is itself process evidence, not a reason to hide the row. List any missing declared paths (from Step 4's re-read of the record, since `role_plan_deliverables_missing` is only a count), backtick-quoted, directly under that role's row.
- `### Assumptions surfaced to the human` — a subsection of `## Process`, present whenever any rendered record has an `[assumed]` bullet: every `[assumed]` bullet from every published record, quoted verbatim (claim + `if wrong → …` clause), grouped by role heading. Omit a role's block if its record has none; omit the whole subsection if no rendered record does (keep `## Process` itself if at least one record exists — the table above still carries the grade counts).

Re-running verification **overwrites** the file — it always reflects the latest check. (For Evergreen squads, note in the Verdict paragraph which iteration was verified.)

## Step 7 — Report and route

Print to the user: the per-signal table (signal · status · evidence pointer), the role-deliverables table, the process table (only if you rendered one — see Step 6), and the verdict line. Then suggest exactly one next step:

- `met` → *"Goal met — verification recorded in `.squad/verification.md`. Safe to declare done."*
- `partial` → name the failing/unchecked signals and the roles whose scopes serve them: *"Re-dispatch [roles] via `/cheeky-squad-os:squad-spawn`, or resolve the NEEDS-HUMAN items, then re-verify."*
- `unmet` → *"No signal passed — re-check the dispatch happened and the roles wrote into their scopes, then re-dispatch via `/cheeky-squad-os:squad-spawn`."*

## Refusals

- **No goal / empty roster:** refuse per preflight.
- **"Just mark it done":** refuse — *"Verification is evidenced, not declared. Show me the evidence or accept the NEEDS-HUMAN rows."* Write nothing.
- **Asked to fix a failing deliverable:** decline and route to `squad-spawn` — judging and fixing in the same pass corrupts both.

## What this skill does NOT do

- Does not modify `.squad/goal.md` (that's `squad-goal`) or `.squad/roster.json` (that's `squad-roster`).
- Does not dispatch or re-dispatch workers (that's `squad-spawn`).
- Does not replace synthesis — synthesis tells you *what was produced*; verification decides *whether it's done*.

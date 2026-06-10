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
3. **One artifact of record.** The verdict lives in `.squad/verification.md`. You write that file and nothing else.

## Preflight — refuse if not ready

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."* and stop.
2. Read `.squad/roster.json`. If absent or `roles` is empty: refuse with *"Roster is empty. Run `/cheeky-squad-os:squad-role` to generate at least one role."* and stop.
3. Note the goal's `mode` from frontmatter (recorded in the verdict; Evergreen squads verify the latest iteration).

## Step 1 — Run the evidence scaffold

From the **project root** (file_scope globs are project-relative), run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/squad-verify/scripts/verify.sh" .squad/roster.json .squad/goal.md
```

It emits one JSON object per line:

- `{"signal": "<text>", "status": "unverified"}` — one per Definition-of-done bullet
- `{"role": "<name>", "scope": […], "files_found": N, "role_goal_present": bool}` — one per active role
- `{"summary": true, "roles": N, "signals": N, "errors": K}` — final line

If the script exits non-zero, surface its stderr to the user verbatim (it names the missing prerequisite — usually `jq`, the goal, or the roster) and stop.

## Step 2 — Judge each signal

For **each** signal line, gather evidence with read-only tools and assign exactly one status:

| Status | When | Evidence you must record |
| --- | --- | --- |
| **PASS** | The signal is observably true right now | The file path you read, or the command + output that proves it |
| **FAIL** | The signal is observably false, or the artifact it names is missing | What you looked for and what you found instead |
| **NEEDS-HUMAN** | Not mechanically checkable from this machine (judgment calls, external systems, live metrics you can't query) | One line on what a human must check, and how |

How to gather evidence:

- If the signal names a **file or artifact** ("report exists at…", "all findings documented in…") — `Read` it. Existing and non-empty with the expected content shape → PASS.
- If the signal names a **countable or runnable check** ("all tests pass", "≥ N entries", "lint is clean") — run the read-only command it implies via Bash and quote the relevant output.
- If the signal names an **external or judgment-based measure** ("converts at >5%", "stakeholder approves", "Lighthouse ≥ 90" when you can't run Lighthouse) — NEEDS-HUMAN. Do not infer it from proxies.

Never average, round, or stretch. A signal that is 90% true is FAIL (or NEEDS-HUMAN if the last 10% isn't checkable) — the goal schema demands signals "checkable without judgement calls", and you are the check.

## Step 3 — Check role deliverables

From the per-role lines, build the deliverables table: role, scope, `files_found`, `role_goal_present`. Then:

- A role with `files_found: 0` produced **nothing inside its scope** — flag it prominently; its workstream is almost certainly the cause of any FAIL.
- A role with `role_goal_present: false` was dispatched without its contract — flag it; the squad's decomposition has drifted from the roster.
- Cross-check each role-goal's **Owned outputs** section (read `.squad/role-goal-<name>.md`): named artifacts that don't exist are FAIL evidence for whichever signal they serve.

## Step 4 — Compute the verdict

| Verdict | Condition |
| --- | --- |
| `met` | Every signal is PASS |
| `partial` | At least one PASS, and at least one FAIL or NEEDS-HUMAN |
| `unmet` | No signal is PASS |

Zero parseable signals (the script reported `"signals": 0`) → verdict `unmet`, with one explanatory row: *"goal has no parseable Definition of done — run `/cheeky-squad-os:squad-goal` to add observable signals"*. Never invent signals to judge.

## Step 5 — Write `.squad/verification.md`

Write the file using the schema in `templates/verification.md`:

- Frontmatter: `verdict` (met|partial|unmet), `verified_at` (current UTC, ISO-8601), `goal_mode`, `signals_pass`, `signals_fail`, `signals_human` (counts).
- Body: one `## Signal: <text>` section per signal with **Status / Evidence / Notes**, the `## Role deliverables` table, and a closing `## Verdict` paragraph in plain language.

Re-running verification **overwrites** the file — it always reflects the latest check. (For Evergreen squads, note in the Verdict paragraph which iteration was verified.)

## Step 6 — Report and route

Print to the user: the per-signal table (signal · status · evidence pointer), the role-deliverables table, and the verdict line. Then suggest exactly one next step:

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

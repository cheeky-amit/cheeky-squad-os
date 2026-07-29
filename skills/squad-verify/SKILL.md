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

**The load-bearing invariant (hard rules #14, #15): a role can never mint the human's ruling.** A role can open an escalation (`status: escalated` on its own engagement record) but it can never close one — there is no `resolved` status and no `resolution:` field anywhere a role writes. The ruling on an open escalation, and the attestation that converts a NEEDS-HUMAN row to `PASS (attested)`, exist in exactly one place: the `resolved_escalations` list and the quoted rulings inside `.squad/verification.md`, written by you and only you. Escalation is evidence generation, never decision (hard rule #10 holds unchanged). The residual hole — a role flipping its own `escalated` back to `active` — is behaviorally identical to never having stopped, which is already the acknowledged aspirational half of #14; what no role can ever do is manufacture your ruling.

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
- `{"summary": true, "roles": N, "signals": N, "errors": K}` — final line, **plus `"escalations_open": M`** whenever at least one active role has ever published an engagement record of any status (this run or a prior one); omitted entirely, not `0`, otherwise (the absence contract). `verify.sh` computes this itself, mechanically, by reading `.squad/role-plan-*.md` (which roles are `status: escalated`, keyed by filename) and `.squad/verification.md` (the `resolved_escalations` list) — the two inputs neither of which a role controls: `escalations_open = |escalated roles| − |those roles named in resolved_escalations|` by set difference, never negative. Trust this number; Step 2.5 below reads the underlying records too, but for their *content* (to build `## Escalations`), not to re-derive this count.

If the script exits non-zero, surface its stderr to the user verbatim (it names the missing prerequisite — usually `jq`, the goal, or the roster) and stop.

## Step 2 — Read the engagement records (process evidence, hard rule #11)

`verify.sh` adds eight keys to a role's per-role line, but only for a role that has published `.squad/role-plan-<name>.md` — omitted **entirely**, not `false`/`0`/`null`, when it hasn't (the absence contract: a project with no records produces the same keys as a pre-#11 run — the one deliberate value change is `files_found`, see Step 4):

- `role_plan_present` — always `true` when present at all; the key's absence is what "no record" looks like, never a `false`.
- `role_plan_status` — the record's frontmatter `status`, passed through verbatim (`active` | `amended` | `escalated` — the script does not special-case the value, so an unrecognized string still comes through; Step 2.5 is what acts on `escalated`).
- `role_plan_frontmatter_role_match` — `false` if the record's frontmatter `role:` disagrees with the filename. The filename still wins (per `templates/role-plan.md`), but a mismatch is a squad-authoring defect — `verify.sh` has already folded it into the run's `errors` count, and this skill flags it too (Step 4).
- `role_plan_assumption_grades` — `{"confirmed": N, "reported": N, "inferred": N, "assumed": N}`, one count per evidence grade across the record's `## Assumptions`.
- `role_plan_deliverables_missing` — a **count** of `## Deliverables` bullets whose backtick-quoted path isn't on disk. It's a count, not the paths — `Read` the record's `## Deliverables` section directly for which ones.
- `role_plan_assumed_risks` — an array of the `if wrong → …` **target text only**, one per `[assumed]` bullet — not the claim. To quote a full bullet (claim + clause) you must `Read` the record's `## Assumptions` section directly; the array only tells you a match is worth checking for.
- `role_plan_fired` — the record's frontmatter `fired:` value, verbatim; empty string unless `role_plan_status == "escalated"` (hard rule #14).
- `role_plan_hand_back_sections_present` — `{"what_happened": bool, "state_of_work": bool, "what_would_unblock": bool}`, one flag per escalation hand-back heading (`## What happened` / `## State of the work` / `## What would unblock`, `templates/role-plan.md`) — `true` only if the heading exists **and** has non-blank body content, so a bare unfilled heading reads as absent, not present. Populated for every record regardless of status; an `active`/`amended` record simply shows all-`false` (it never had these sections to fill).

Build the process table from these: role · record published (yes/no) · `role_plan_status` · the four grade counts · `role_plan_deliverables_missing` · how many entries in `role_plan_assumed_risks`. A role with no record at all is not automatically a failure — Step 0 is a hook gate on the role's *other* writes, not a content requirement this skill enforces — but say so plainly in its row: without a record there is no process evidence for that role's workstream, only whatever artifact evidence Step 4 finds.

**The forcing rule.** For every dispatched role with a record, treat each entry in `role_plan_assumed_risks` as a candidate target. If a Definition-of-done signal names, or is only supported by, one of those targets, it **cannot PASS on the strength of that same role's own output** — cap it at NEEDS-HUMAN in Step 3. When you cap a signal this way, `Read` that role's record's `## Assumptions` section to find and quote the matching `[assumed]` bullet **verbatim** — claim and `if wrong → …` clause together — as the evidence. `role_plan_assumed_risks` only tells you a match exists; it is not itself the quote. A role's own guess cannot certify itself by producing the very artifact the guess was about — that is what "if wrong" was warning you against.

## Step 2.5 — Escalations (hard rule #14)

**Read the existing `.squad/verification.md` now, if it exists — before Step 6 overwrites it.** Pull its frontmatter `resolved_escalations` list and, for any role already there, its prior `## Escalations` entry (the `Ruling:` a human already gave). Step 6 overwrites the file; a ruling recorded in a prior pass must carry forward into this one or a re-verify silently un-rules it. This is read-only input here — you only ever add to `resolved_escalations` in Step 6, when Step 5.5 produces a new ruling.

For every active role whose record shows `role_plan_status == "escalated"`:

1. `Read` that role's record directly for the content the script only flags the presence of: the frontmatter `fired:` value (`role_plan_fired` gives you the string already — no need to re-read for this one), and the three hand-back sections' actual text — `## What happened`, `## State of the work`, `## What would unblock` (`role_plan_hand_back_sections_present` only tells you which exist and are non-blank; it is not itself the content).
2. Determine **which Definition-of-done signal(s) this escalation blocks**, the same way Step 3's forcing rule will: does any signal name, or is any signal only supported by, this role's work? Note the signal text(s), or "no signal directly; blocks `met` on `escalations_open` alone" if none does. This becomes the `## Escalations` entry's `Blocks:` field (Step 6) — decide it once here, reuse it in both places rather than re-deriving it in Step 3.
3. Check whether this role's name is already in the `resolved_escalations` list you read above. If it is, this escalation is **resolved** — carry the prior `Ruling:` forward unchanged (do not re-prompt for it in Step 5.5). If it is not, this escalation is **open**.

`escalations_open` (the count Step 1 already gave you from `verify.sh`) should equal the number of roles you found **open** here — if it doesn't, `verify.sh`'s reading of `resolved_escalations` disagreed with yours; trust the script's count (it reads the file the same way you just did) but flag the mismatch rather than silently picking one.

## Step 3 — Judge each signal

For **each** signal line, first check it against two forcing rules, in order:

1. **Step 2's rule.** If this signal names, or is only supported by, an entry in any dispatched role's `role_plan_assumed_risks`, the ceiling is **NEEDS-HUMAN** — quote the matching `[assumed]` bullet verbatim, read from the record (the target string alone is not the quote), and move on.
2. **Step 2.5's rule.** If this signal is one of the ones Step 2.5 identified as `Blocks:`-ed by a role with an **open** escalation (hard rule #14), the ceiling is **NEEDS-HUMAN** — evidence is the record's `fired:` field (`role_plan_fired`) quoted verbatim, plus a pointer to `.squad/role-plan-<role>.md`. A blocked deliverable cannot certify the very signal it was blocked on.

If neither rule caps it, gather evidence with read-only tools and assign exactly one status:

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
| `met` | Every signal is `PASS` **or** `PASS (attested)`, **and** `escalations_open == 0` |
| `partial` | At least one `PASS`/`PASS (attested)`, and (at least one FAIL or NEEDS-HUMAN, **or** `escalations_open > 0`) |
| `unmet` | No signal is `PASS` or `PASS (attested)` |

`escalations_open` gates `met` **on its own**, independent of any individual signal — hard rule #14: "an open escalation blocks a `met` verdict," full stop, even if every signal happens to PASS on evidence that never touched the escalated role's work. When no active role has ever published an engagement record anywhere in the squad, `escalations_open` is absent (never `0`); it imposes no condition, and a squad that never used the feature is judged exactly as a pre-#14 run was. `PASS (attested)` (Step 5.5) counts exactly like machine `PASS` for the verdict math — it is a different evidence *class*, never a different verdict weight.

Zero parseable signals (the script reported `"signals": 0`) → verdict `unmet`, with one explanatory row: *"goal has no parseable Definition of done — run `/cheeky-squad-os:squad-goal` to add observable signals"*. Never invent signals to judge.

## Step 5.5 — The attestation protocol (hard rule #15)

**Zero ritual when nothing is wrong.** If every signal from Step 3 is already machine-PASS and Step 2.5 found zero escalations (open or otherwise) — skip this entire step. Print nothing, ask nothing. That is the only way `met` gets reached, and a gate everyone learns to click through is worse than none.

Otherwise, for every NEEDS-HUMAN signal and every open escalation, offer the human a chance to put it on the record — this is the same evidence bar the machine had to meet, applied to the human. Ask signals and escalations **separately** (they write to different places — see below), but if Step 2.5 already tied a NEEDS-HUMAN signal to a specific open escalation (its `Blocks:` field), ask about that escalation once and apply the same answer to both — don't make the human explain the same thing twice.

> *"Signal `<signal text>` is NEEDS-HUMAN. Can you attest to it? Tell me what you checked and what you found — I'll record it verbatim, with your name and today's date, as `PASS (attested)`, distinct from anything machine-verified."*
>
> *"The `<role>` escalation — fired: `<the bullet, verbatim>` — is still open. What's your ruling? Tell me what you checked, what you decided, and why — I'll record it verbatim, with your name and today's date, as this escalation's `Ruling:`."*

- **A concrete answer** (names what they checked, what they found/decided) → record it **verbatim**, with attribution (their name/handle — ask if it isn't already known from context) and today's date (UTC, ISO-8601).
  - **For a signal:** tag its Status `PASS (attested)` — the only attested tag that exists; there is no attested FAIL.
  - **For an escalation:** write it as the `Ruling:` field, plain — not a status tag. The ruling may affirm ("checked, it's correct, ship it") or waive ("this deliverable was never actually necessary, drop it") — either way it's recorded verbatim and it still closes the escalation (the role's name goes into `resolved_escalations`, Step 6). Never invent a tag for it; the free-form quoted ruling **is** the record.
- **A bare assertion** ("it's fine", "trust me", "yes") → push back **exactly once**: *"I need what you checked and what you found, not just an assertion — even one line is enough."*
- **Whatever the human says after that single push-back** — even if still bare — gets recorded verbatim, attributed and dated, same as above, with a Notes line noting no supporting detail was given. **Do not push back a second time. The human is never blocked, they are put on the record.**
- **An explicit decline** ("skip", "not now", "leave it") → leave the item exactly as Step 3/2.5 found it (NEEDS-HUMAN / `Ruling: UNRESOLVED`). Never fabricate an attestation for silence or a decline.

`PASS (attested)` is **permanently distinct** from machine-verified `PASS` — the tag, the attribution, and the date travel into Step 6's write and Step 7's report and never get merged into an unqualified `PASS`. A future reader must always be able to tell "the machine checked this" from "a human said so, here's what they said." Same discipline for a `Ruling:` — it is never blank once given, and never rewritten to look like it was always there.

A ruling on an **escalation** IS the human's decision that closes it — it goes into `resolved_escalations` in Step 6, which is the only thing that ever removes a role name from `escalations_open`. No role writes that list, ever (the load-bearing invariant, above).

## Step 6 — Write `.squad/verification.md`

Write the file using the schema in `templates/verification.md`:

- Frontmatter: `verdict` (met|partial|unmet), `verified_at` (current UTC, ISO-8601), `goal_mode`, `signals_pass`, `signals_fail`, `signals_human` (counts). No frontmatter field is added for the process feature. **New for #14/#15, and only when at least one active role has an engagement record anywhere in the squad (this run or a prior one) — omitted entirely, not `0`/`[]`, otherwise (the absence contract, and the two fields are omitted TOGETHER — never one without the other):** `escalations_open` (int) and `resolved_escalations` (YAML list, one role name per line — the cumulative set of role names a human has ever ruled on for this squad; Step 2.5's carried-forward list plus any this pass's Step 5.5 rulings added). **No role writes either field, ever — this is the only place either exists.**
- Body sections, in this exact order (the fixed shape `templates/verification.md` establishes):
  1. `## Signal: <text>`, one per Definition-of-done bullet, grouped **weakest-evidence-first within this block** (hard rule #15 — a reader meets the weakest evidence before the stronger): every **FAIL** first, then every **NEEDS-HUMAN** (including anything Step 5.5 recorded as `PASS (attested)` — still tier-2 evidence, a human said so rather than a machine, so it renders here, not with machine-PASS), then every machine-verified **PASS** — original goal order preserved *within* each tier.
     - Status line: `**Status:** <PASS | FAIL | NEEDS-HUMAN | PASS (attested)>`.
     - Evidence line(s): `**Evidence (machine):** <what you read or ran>` for PASS/FAIL/NEEDS-HUMAN; `**Evidence (human attestation, <date>):** "<verbatim>"` **instead**, only for `PASS (attested)` — never both on the same signal.
     - `**Notes:**` optional, as before.
  2. `## Role deliverables` — the existing table, unchanged.
  3. `## Process` — conditional exactly as before (at least one engagement record anywhere; omit entirely otherwise), including `### Assumptions surfaced to the human` per the existing rule.
  4. `## Escalations` — render only if Step 2.5 found at least one escalated role (open or resolved this run); omit entirely, not as an empty heading, otherwise. One `### <role-name>` block per escalated role, **most-recently-fired first**: `**Fired:**` (the record's `fired:` field, quoted), `**Blocks:**` (Step 2.5's determination — the signal(s) this escalation blocks, or the "no signal directly…" line), `**Ruling:**` (`UNRESOLVED`, or the human's ruling verbatim with the same evidence-attribution split: `**Evidence (human attestation, <date>):** "<verbatim>"`). This section sits here — after Process, right before Verdict — because it is itself unresolved/weak evidence and belongs adjacent to the conclusion it's still blocking, not interleaved among the numbered signals above.
  5. `## Verdict` — **always last.** One plain-language paragraph: the verdict, why, and the single suggested next step.

A ruling recorded here and the matching name added to `resolved_escalations` **must move together** — one without the other is a malformed resolution; flag it in the Verdict paragraph rather than silently treating the escalation as closed.

Re-running verification **overwrites** the file — it always reflects the latest check, but Step 2.5's read of the *prior* file's `resolved_escalations` (and prior rulings) is what keeps a human's earlier decision from being silently dropped on re-write. (For Evergreen squads, note in the Verdict paragraph which iteration was verified.)

## Step 7 — Report and route

Print to the user in the **same order** Step 6 wrote to disk: FAIL signals, then NEEDS-HUMAN signals (weakest-first within the signal block, hard rule #15), then PASS signals, then the role-deliverables table, then the process table (only if you rendered one), then `## Escalations` (only if rendered), then the verdict line last. Then suggest exactly one next step:

- `met` → *"Goal met — verification recorded in `.squad/verification.md`. Safe to declare done."*
- `partial`, escalations open → include: *"[N] escalation(s) open — [roles]. Attest to them now (I'll ask you what you checked), or leave them for later and re-verify when you have an answer."*
- `partial`, no escalations open → name the failing/unchecked signals and the roles whose scopes serve them: *"Re-dispatch [roles] via `/cheeky-squad-os:squad-spawn`, or resolve the NEEDS-HUMAN items, then re-verify."*
- `unmet` → *"No signal passed — re-check the dispatch happened and the roles wrote into their scopes, then re-dispatch via `/cheeky-squad-os:squad-spawn`."*

## Refusals

- **No goal / empty roster:** refuse per preflight.
- **"Just mark it done":** refuse — *"Verification is evidenced, not declared. Show me the evidence or accept the NEEDS-HUMAN rows."* Write nothing.
- **Asked to fix a failing deliverable:** decline and route to `squad-spawn` — judging and fixing in the same pass corrupts both.
- **A role's own record claims resolution:** ignore it. There is no `resolved` status and no `resolution:` field in the engagement-record schema — a role cannot write either, and if one somehow appears, treat it as noise, not a ruling. Only a name in `.squad/verification.md`'s own `resolved_escalations` list, written by this skill, closes an escalation.
- **Pushed for a second time on a bare attestation:** don't. Step 5.5 is exactly one push-back, then record verbatim regardless. Refusing a second time contradicts "the human is never blocked."

## What this skill does NOT do

- Does not modify `.squad/goal.md` (that's `squad-goal`) or `.squad/roster.json` (that's `squad-roster`).
- Does not dispatch or re-dispatch workers (that's `squad-spawn`).
- Does not replace synthesis — synthesis tells you *what was produced*; verification decides *whether it's done*.
- Does not treat any role-written field as a ruling — `resolved_escalations` and every attested quote exist only inside `.squad/verification.md`, written by this skill and no other (hard rules #10, #14, #15).

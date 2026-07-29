---
name: squad-world
description: Use when the human wants to record, inspect, settle, or research what the squad believes about the world — phrases like "the squad should know X", "note that X is true", "what does the squad believe about X", "show the world model", "what's disputed", "settle the disagreement about X", "adjudicate X", "that's no longer true", "retire the belief about X", "research the domain first", "research whether X changed". Manages .squad/world/claims-<owner>.md, the shared belief ledger — the human's own beliefs and rulings (claims-user.md, the only file this skill writes freely, no gate) plus a read/adjudicate surface over every role's own claims-<role>.md, plus — via the **research** verb, gated by two human approvals — claims-research.md, the ledger's findings file. seed/inspect/adjudicate/retire are NOT onboarding steps, triggered on demand; research is the one exception — offered once by squad-onboard with the goal already approved, and re-runnable on demand thereafter.
version: 0.1.0
author: cheeky-squad-os
license: MIT
allowed-tools: [Read, Write, Edit, Bash]
compatible-with: [claude-code, agentskills-1.0]
---

# squad-world

Every other skill in this plugin acts on the human's behalf — it writes what a role or a flow decided. `squad-world` is different: **the human authors this artifact.** That is this skill's reason to exist at all (`CONTRIBUTING.md`'s skill-count rule: a new skill only when the human is the artifact's own author, not a delegate acting for them). `claims-user.md` is the human's own ledger — their beliefs, and the rulings that settle disputes between roles' beliefs. No role ever writes to it; the `PermissionRequest` hook refuses the reserved owner name `user` structurally, so this skill is the one place in `.squad/world/` trusted to write there at all.

## What this is

`.squad/world/claims-<owner>.md` — one file per owner, ownership **positional by filename**, forgery blocked structurally by the hook (a role named `user` or `research` is refused those files outright; every other role is granted exactly its own `claims-<agent>.md`, and only once its engagement record exists). Two owners are not roles:

- **`claims-user.md`** — yours. The human's own beliefs and every ruling that has ever settled a dispute.
- **`claims-research.md`** — the ledger's findings file. Written only by this skill's **research** verb, and only through its two human gates — never freely, never by a role (the hook refuses the reserved owner name `research` to every role, the same structural refusal it applies to `user`). Absent or empty on any squad that has never run research.

The disambiguation this file answers: `goal.md` is what the squad **wants** true. `world/` is what the squad **knows** true, and how it knows it. If it's still true after everyone leaves the room, it belongs here — not in a hand-off, not in an engagement record.

**Belief block** (one per `## Belief:` heading, any number per file):

```markdown
## Belief: <kebab-key>

Claim: <one sentence, falsifiable>
Source: <file, command, URL, tool read, or person>
Grade: confirmed | reported | inferred | assumed
Observed: <ISO-8601 date>
Status: live | superseded | retired
Notes: <optional>
```

`Grade` is the **same four-value vocabulary** as the engagement record (`templates/role-plan.md`) — one glossary across the plugin, never a second one, never a number:

- **confirmed** — checked directly, right now. Source names the file/command/URL that proves it.
- **reported** — carried in from somewhere else. Source names who or what said it.
- **inferred** — reasoned from something else. Source names what it was reasoned from.
- **assumed** — nothing backs it yet. Source can be `"none"`, but say so plainly rather than inventing one.

## Hard rule #13 — a belief with no source is a rumor

This is enforced by `world.sh`, mechanically — not by this skill asking nicely. `Claim`, `Source`, `Grade`, and `Observed` are all required; a block missing any one of them, carrying a `Grade` outside the four values above, or carrying a `Status` outside `live | superseded | retired`, is **invalid** and is excluded from every projection: it never reaches `world.sh --index`, it never reaches a spawn prompt, and this skill's **inspect** operation lists it by name with exactly what is missing so it can be fixed on disk.

Rule #13 under its heaviest load: `claims-research.md` is the single most tempting place in this plugin to write an ungrounded claim. `world.sh` carries a per-owner grade ceiling for exactly that file — a block there graded `inferred` or `assumed` is **invalid**, on top of the four checks above. Research may produce only `confirmed` or `reported` (see the **research** verb below); the ceiling is parser-enforced, not skill-promised.

`disputed` is **derived, never writable** — no block anywhere ever carries `Status: disputed`, and this skill never writes that word either. Two `live` blocks under the same key from **different owners** *are* the dispute, computed by `world.sh` from what's already on disk. Two live blocks under the same key from the *same* owner are a different problem — a duplicate live key inside one file — and `world.sh` reports that as invalid, not as a dispute.

## Running `world.sh`

Every operation below except a from-scratch **seed** reads the ledger through `world.sh` (bash+awk+jq, `skills/squad-verify/scripts/verify.sh`'s pattern exactly: read-only, never writes a file, one JSON object per line, non-zero exit + stderr on a real preflight failure). Run it **from the project root** — like `verify.sh`, it resolves `.squad/world/` project-relative and takes no positional argument naming it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/squad-world/scripts/world.sh"
```

The plain (non-`--index`) mode — what **inspect** and **adjudicate** both use — emits, across every `.squad/world/claims-*.md` it finds. Each line's **distinguishing key holds the meaningful value** (the same trick `verify.sh` uses for `signal`/`role`), so there is no separate `key` field to read; the belief key *is* the value of `belief` / `invalid` / `conflict`:

| Line | Shape | One per |
| --- | --- | --- |
| belief | `{"belief":"<key>","owner":"<owner>","claim":"…","source":"…","grade":"confirmed\|reported\|inferred\|assumed","observed":"<ISO-8601>","status":"live\|superseded\|retired","notes":"…"}` | **valid** block, any status. `notes` is always a string — `""` when absent, never `null`. |
| invalid | `{"invalid":"<key>","owner":"<owner>","file":"<path>","reasons":["missing_claim"\|"missing_source"\|"missing_grade"\|"missing_observed"\|"bad_grade"\|"bad_status"\|"duplicate_live_key"\|"research_grade_ceiling", …]}` | block that fails validation. This line **is** hard rule #13's mechanical guarantee made visible. `research_grade_ceiling` is the per-owner ceiling below and appears for no owner but `research`. |
| conflict | `{"conflict":"<key>","owners":["<owner-a>","<owner-b>", …]}` | key with ≥2 **live** blocks from **different** owners. The only place `disputed` exists as a fact — never a field a block sets on itself. |
| summary | `{"summary":true,"files":N,"beliefs":N,"live":N,"invalid":N,"conflicts":N}` | run; always last. `files` counts claims files parsed, `beliefs` counts valid blocks of every status, `live` only the live ones, `conflicts` the disputed keys. |

**Silence means one specific thing.** Plain mode prints nothing at all — not even a summary — when `.squad/world/` is absent, or when it holds no parseable `## Belief:` block anywhere. It does **not** go quiet just because nothing is currently live: a ledger whose every block is invalid still prints its `invalid` lines and its summary, which is the whole point — the beliefs have vanished from every prompt and **inspect** is where the human finds out why. (`--index` is the opposite: it goes silent the moment nothing is live, because a prompt has nothing to be told.)

`world.sh --index [--cap N] [--disputed-cap M]` is the separate, token-disciplined projection `squad-spawn` bakes into role prompts — capped (default 50), 80-byte-truncated index lines (a byte cap, so it is identical at every locale, and the cut never splits a UTF-8 character), recency-ordered, full blocks for up to `M` (default 5) disputed keys, explicit `+N more on disk` / `+K more disputed — run squad-world` tails, and the invalid count on its own line. **This skill never calls `--index`** — you are working at the terminal with the human, not budgeting a prompt, and `--index`'s truncation would hide exactly the detail **adjudicate** needs to show both sides in full. Always use the plain mode above.

If `world.sh` exits non-zero, or `jq`/`awk` aren't available, surface its stderr verbatim and stop — same discipline `squad-verify` applies to `verify.sh`.

## Verbs

Operations are: **seed**, **inspect**, **adjudicate**, **retire**, **research**. There is no **prune** — see below.

### seed

**Trigger: the human has something to say — not an onboarding question.** The world-seed onboarding question was cut as ceremony (it taxed every user for a feature few used on day one); this verb is what carries seeding instead, invoked whenever the human says something shaped like "the squad should know X" / "note that X" / "for the record, X is true."

1. Confirm `.squad/world/` exists (`mkdir -p .squad/world` if not).
2. Get what a valid block needs, asking only for what's missing from what the human already said:
   - **Claim** — restate it as one falsifiable sentence; confirm the restatement rather than assuming it's right.
   - **Key** — propose a kebab-case key from the claim; let the human override.
   - **Source** — ask directly if not already implied ("Where's that from — a file, a tool read, someone who told you?").
   - **Grade** — infer it from how the human is talking about it (they just looked something up themselves → `confirmed`; someone told them → `reported`; they're reasoning it through → `inferred`; they're guessing → `assumed`), but say your inference out loud and let them correct it. Never leave it unstated.
3. `Observed` defaults to today (UTC, ISO-8601) unless the human names a different date.
4. **Check for a collision before writing.** Run `world.sh` (above) and check both `claims-user.md` for an existing `live` block under the same key, and every other owner's `claims-*.md` for the same. A collision with the human's own prior belief is a straightforward overwrite (confirm, then update `Status` on the old block to `superseded` in the same edit). A collision with a **different owner's** live belief under the same key is the dispute forming in real time — don't silently add a second live block under a contested key; stop and offer **adjudicate** instead.
5. Append the block to `claims-user.md` (create the file, containing just this block, if it's the first entry).
6. Confirm: *"Belief recorded — `<key>`, grade `<grade>`."*

### inspect

Render `world.sh`'s output as a table for the human — this is the read surface, not a summary you write freeform.

1. Run `world.sh` (plain mode). **Empty output** means no ledger at all — print *"No world model yet. Run squad-world when there's something the squad should know."* and stop. Output with `invalid` lines but `"live": 0` is a different state entirely and must never be reported as "nothing here": the squad wrote beliefs and every one of them is malformed. Go to step 4 and show them.
2. **Beliefs by owner** — one table, every `live` belief: owner · key · claim · grade · observed. (Full claim text, not truncated — this skill has no token budget to protect; that discipline belongs to `world.sh --index`, not here.)
3. **Disputed keys, called out separately and prominently** — for every key `world.sh` reports as `conflict`, show every owner's live block side by side in full (claim / source / grade / observed / notes). This is the exact same view **adjudicate** opens with, so a human can go straight from "what's disputed" into settling it. Ask: *"Want to adjudicate any of these now?"*
4. **Invalid blocks, listed with what they're missing** — owner · key · file · each `reasons` code spelled out in English (`missing_source` → "no `Source:` line", `bad_grade` → "`Grade:` is not one of the four", `bad_status` → "`Status:` is not live/superseded/retired", `duplicate_live_key` → "this owner already has a live block under this key", `research_grade_ceiling` → "`Grade:` is `inferred` or `assumed`, which research may not assert — only `confirmed` or `reported`; if the human wants this on the ledger it is theirs to assert, via **seed**, into `claims-user.md`") · one line: *"excluded from every projection until this is fixed on disk."* A block whose `## Belief:` heading carried no key at all is not reported here — there is nothing to report it under; it is simply absent from the run, and the human finds it by reading the file.
5. One summary line, read straight off `world.sh`'s `summary`: `files` · `beliefs` · `live` · `conflicts` · `invalid`. Do not recount them yourself.

### adjudicate

**The load-bearing verb.** Two live blocks under one key are never averaged, never auto-resolved, never latest-wins — this is hard rule #13's second half, and it is a hard refusal, not a preference.

1. Identify the disputed key — from a just-run **inspect**, or the human names one directly ("settle the disagreement about X").
2. Run `world.sh` and pull every **live** block under that key across every owner, including `claims-user.md` if the human already holds one there.
3. **Show both sides with their provenance, in full** — Claim, Source, Grade, Observed, Notes, owner-labeled, neither side summarized thinner than the other. The human needs equal footing to judge; a paraphrase from you is not equal footing.
4. **The human rules.** Ask which claim stands, whether it's a synthesis of both, or something neither side said. Do not propose a resolution yourself and ask for a rubber stamp — present the evidence, then wait. (Same spirit as hard rule #10: the human decides, never the machine, never you on the human's behalf.)
5. Write the ruling as a block in `claims-user.md` under the same key (new block, or update the human's existing one): `Claim` is the ruling itself, `Source` names the adjudication ("human ruling, <date>" or however the human would rather phrase it — ask if unstated), `Grade` reflecting how the human actually knows this now (typically `confirmed` — they just decided it — but let them say otherwise), `Observed` today.
6. **Mark every losing block `superseded` — with per-edit consent, in the same turn.** Do not batch this silently. For each losing block: name the exact file and key, show the one-line diff (`Status: live` → `Status: superseded`), and get an explicit yes before writing it. Never supersede a block the human hasn't specifically approved superseding, even when the ruling seems to obviously settle it.
7. Confirm the full outcome: *"Ruling recorded in `claims-user.md` under `<key>`. Superseded: `<owner>/<key>` in `claims-<owner>.md`"* (one line per superseded block).

**Ownership note on step 6.** `claims-user.md` is the only file this skill writes freely. Every other `.squad/world/claims-<role>.md` belongs, structurally, to that role — the hook grants it there and nowhere else. Editing one to flip a single `Status` field during an adjudication is this skill acting as the human's delegate for exactly that one field, with consent obtained per edit, not a standing grant: never touch anything else in that file, and never open it outside a seed-collision check or an adjudication the human is actively running.

### retire

Mark a belief no longer true — it stays on disk (no delete), status changes.

1. Identify the belief: key, and owner if the key has blocks from more than one (ask which, if ambiguous).
2. If it's the human's own (`claims-user.md`): edit directly, `Status: live` → `retired`. No extra ceremony — it's the human's own file.
3. If it's a role's: same per-edit consent as adjudicate step 6 — show the diff, get the yes, then write.
4. Confirm: *"`<key>` (`<owner>`) marked retired."*

### research

**The ledger's primary producer — findings from the world, not the human's own say-so.** Invoked by `squad-onboard`'s mode-inference message (rides that existing beat — not a new one) once the goal is confirmed, or directly by the human re-running it later ("research whether X changed", "research the domain first"). Writes only to `.squad/world/claims-research.md`, using the exact same block schema as every other claims file (`templates/world-claims.md`, verbatim — no second schema). Two gates, both the human's (R1) — neither is a yes/no prompt; "adjusted" means a real edit.

**Gate 1 — the plan.** Derive 3–6 questions from the already-approved goal: one per checkable noun-phrase in the outcome, one per Definition-of-done signal whose baseline or threshold could be stale, one open slot for user-supplied documents. Cut any question whose answer would not change the decomposition or a role. Show them numbered, each with a proposed source annotation — a visibly absent class marked inline (`source: Klaviyo connector (not connected — supply an export or drop the question)`) — and print the cost at the offer: roughly how long (a few attended minutes) and roughly how many sources (up to 4 classes per question), before any squad work begins. Accepting wholesale is one word (`go`); skipping is one word (`skip`) and the decomposition proceeds from priors exactly as it does today. The human may instead edit, add, or drop questions in the same reply.

**Execution.** Runs in the main session. Four source classes, each degrading independently and honestly:

| Class | Dispatch | Grade ceiling | If unavailable |
| --- | --- | --- | --- |
| Web search/fetch | inline or fanned subagent | `reported` (a page attests; it does not prove) | **skipped** — no network, stated at gate 2, never guessed |
| Local codebase / project files | inline or fanned subagent | `confirmed` (Source names the file) | always available |
| Connected MCP tools | inline, main session (holds the connectors) | `confirmed` (Source names the tool call + object + date) | **unresearchable** — no connector; annotated at gate 1, or `unresearchable — no <tool> connector` at gate 2 |
| User-supplied documents | paths/pastes given at gate 1 | `reported` (Source names the doc) | class unused if none supplied |

Independent web/codebase questions MAY fan out as anonymous subagents, grouped per class, **bounded at ≤4 concurrent**. Each dispatch bakes the full `.squad/goal.md` (rule #4), the question verbatim, the grade discipline, R2 below, and the output contract: return candidate belief blocks (Claim/Source/Grade/Observed) in the final message only — no write duties, no write permissions. Researchers carry no registered `agent_type`, so every `.squad/` write they might attempt structurally defers to the human, same as any other unregistered caller. MCP and user-document questions run inline in the main session, which holds the connectors.

**The grade ceiling is absolute — research writes only `confirmed` and `reported`, never `inferred`, never `assumed`.** R3 forbids a synthesized claim wearing a finding's clothes, and `world.sh` now enforces this mechanically (see Hard rule #13 above): a `claims-research.md` block graded `inferred` or `assumed` is **invalid**, same treatment as a missing `Source:` line. Say this plainly: the parser catches that one violation; everything else about this verb is this skill body asking nicely, not a mechanism. If the human wants a synthesis on the ledger, they assert it themselves at gate 2 into `claims-user.md` — that is what it honestly is, and `claims-user.md` carries no ceiling.

**A question no available source can answer is `unanswered`** — never guessed, never backfilled with an `inferred` claim wearing a finding's clothes. It gets exactly three homes, none of them the ledger: the human answers it at gate 2 (→ `claims-user.md`); it becomes a workstream (answering it is the work); or it becomes a `needs:` bullet on whichever role's slice it points at, for dispatch triage to route to the human. It never silently vanishes and never impersonates a finding.

**R2 — the contradiction stop.** Before gate 2, check every `confirmed`/`reported` finding against `.squad/goal.md`. It fires when a finding does one of exactly four things to **text quoted from the goal**:

1. makes a Definition-of-done signal already-true, impossible, or unmeasurable as written;
2. falsifies a factual premise in the outcome paragraph;
3. shows the outcome or a DoD signal requires an act the goal lists under Out of scope;
4. shows the deadline or quality bar in the outcome sentence is unachievable as written.

It does **not** fire on merely-harder, on a better-approach finding (that's composition input, not contradiction), or on a finding that contradicts another *finding* (ordinary conflict — **adjudicate** handles that). **No quoted goal line, no stop** — that is what keeps it from firing on everything. Under fan-out, the stop lands at collection, before anything is presented or written.

When it fires it is the only thing on screen — quote both sides, name the source and grade — and gate 2 is unreachable until ruled:

```text
STOPPED — a finding contradicts the goal. Nothing written; no findings shown until you rule.

  Goal says:  "<quoted line>" — <which DoD signal / outcome clause>, .squad/goal.md
  Found:      <the finding>
  Source:     <source> [<grade>]

  Only you may change the goal (hard rule #1):
  1. amend it            — hands to squad-goal's replace flow with this on the table
  2. reject the finding  — your ruling is recorded in the belief's Notes; dropped or downgraded as you direct
  3. proceed on the record — the belief enters the ledger live; the record shows you both knew
  4. stop here
```

**Label this honestly as an instruction, not a mechanism** — nothing enforces R2 but this skill body; the quote requirement narrows judgment, it does not mechanize "unachievable." Never auto-amends (hard rule #1 makes the goal binding — only the human may change it). On amend, surviving questions are re-derived against the new goal and shown as a one-line delta before gate 1 re-opens.

**Gate 2 — the findings.** Order is fixed: any just-ruled contradiction first, then every other finding as a **full belief block** — Claim, Source, Grade, Observed, Notes — the human is ratifying exact text, not a compressed summary. Then **Unanswered**, with its reason and its three homes above. One reply may: rewrite a Claim (the block gains `Notes: … adjusted by user at gate 2 <date>` — provenance survives the edit), downgrade a Grade, drop a finding, answer an unanswered question, or `discard` everything. **Upgrading to `confirmed` is refused unless the human supplies the proving locator** — the glossary binds the human too. `approve` writes the survivors to `claims-research.md` (created if this is the first run). This write carries no `agent_type` — it is the human's own main-session `approve`, deferred to and executed exactly like any other `claims-user.md` write this skill makes.

**What research hands the decomposition** — owned by `squad-onboard`/`squad-role`, not this skill, stated here so the contract is visible: every survivor's belief key, for the decomposition to cite or mark `(from priors)`; a `confirmed` limiting belief, for a role's `stop:` bullet; an unanswered question, for a role's `needs:` bullet.

**Re-run.** Runs the same two gates again. A new finding under an existing key is written live, same as any claims file — the human resolves the resulting `conflict` at gate 2 or later via **adjudicate**; never auto-superseded. Ends with one question only if a live roster role cites the changed key: *"belief `<key>` changed and role `<r>` cites it — revisit the roster?"* — hands to `squad-roster`/`squad-role` on yes. Never recomposes on its own.

**What this does NOT do — stated plainly.** Not a general-purpose research agent. It researches **to compose a squad, then stops**: no standing monitoring, no research without an approved goal, no autonomous re-run, no crawling beyond the approved plan, no budget knobs, no per-domain question banks.

### No `prune`

There is no sixth verb. Deleting old `superseded`/`retired` blocks outright is housekeeping the human does directly in an editor — this skill only ever changes `Status`, never removes a block from disk.

## Limits — read these before you rely on this

| Limit | What it actually means | What to do about it |
| --- | --- | --- |
| Conflicts are detected only for **identically keyed** beliefs | `world.sh` matches on the literal `<kebab-key>` string. Two roles can hold flatly contradictory beliefs under different keys — `homedics-cvr-is-2-1-percent` vs `conversion-rate-holding-steady` — and nothing anywhere in this system notices; they sit as two unrelated-looking `live` blocks forever. | When seeding or inspecting, skim the full table for anything that *sounds* related, not just an exact key match — this skill cannot do that check for you, and neither can `world.sh`. |
| Grades are **self-reported** | `world.sh` validates that `Grade` is one of the four allowed *values*. It cannot validate that the grade is *honest* — nothing verifies a `Source:` line is truthful, or that a `confirmed` claim was actually checked rather than assumed and mislabeled. | Treat another owner's `confirmed` the way you'd treat any unverified claim from a person — the ledger records what was said, not what's true. |
| The admission criterion — "this deserves to be a belief" — is **unenforceable** | Nothing gates *what* gets written, only whether what's written is well-formed. A role or the human can seed trivia, opinion, or a one-off observation as a permanent ledger entry, and it's syntactically indistinguishable from something load-bearing. | This skill may nudge during **seed** ("is this durable enough to outlive this run?") but never refuses a well-formed block on judgment grounds — that would make the criterion look enforced when it isn't. |

## Non-goals — deliberate, stated so no one goes looking for them

- **No TTL / no staleness decay.** A belief does not rot on a timer. `Observed` records when it was recorded — it is never an expiry clock anything counts down.
- **No semantic contradiction detection.** The identically-keyed limit above, restated because it's the one most likely to bite: "no conflicts shown" never means "no contradictions exist," only "none share a key."
- **No auto-resolution, ever.** A disputed key sits disputed until a human runs **adjudicate** — not on a timer, not by owner priority, not by whichever block was written last. Latest-wins is exactly the behavior this verb exists to refuse.
- **No cross-squad merge.** A parked squad's `world/` moves with it (`squad-goal`'s park/switch) and comes back exactly as it was parked. Nothing anywhere in this plugin merges two squads' belief ledgers into one — see `squad-goal`.

## What this skill does NOT do

- Does not write any role's `claims-<role>.md` except the single-field, per-consent `Status` edits inside **adjudicate**/**retire** above — roles write their own files directly, gated by the `PermissionRequest` hook (hard rule #13's forgery protection: ownership is positional by filename and structurally unforgeable, including against a role literally named `user` or `research`).
- Does not write `claims-research.md` except through the **research** verb's own two gates — never freely the way `claims-user.md` is written, and never by a role (same hook refusal as above).
- Does not run **seed** at onboarding, ever — no seed question anywhere in `squad-onboard` (cut deliberately; see **seed** above). **research** is the one verb that does run at onboarding — once, offered by `squad-onboard` after the goal is confirmed, never before.
- Does not decide a dispute itself — **adjudicate** presents evidence in full; the human rules. **research**'s own contradiction stop (R2) is the same discipline: it hands the ruling to the human, never rules itself.
- Does not delete anything — no `prune` (see above).
- Does not modify `.squad/goal.md` or `.squad/roster.json` — those are `squad-goal` and `squad-roster`. **research**'s contradiction stop can only *offer* an amend path through `squad-goal`; it never edits the goal itself.

---
name: squad-role
description: Use when the user wants to add a teammate to the squad — phrases like "generate a role", "add a teammate", "we need someone who…", "add a researcher/auditor/writer/analyst/scraper to the squad", "create a role for X". Also invoked by squad-onboard once per proposed role during onboarding. Interactive flow that asks what the role does, what files it owns, what tools it needs, what model, and what scope — then writes a subagent definition to .claude/agents/<role-name>.md and registers it in .squad/roster.json. The role file is reusable as both a subagent (via Agent tool) and an Agent Teams teammate.
version: 0.1.0
author: cheeky-squad-os
license: MIT
compatible-with: [claude-code, agentskills-1.0]
---

# squad-role

You generate one bespoke role per invocation. Roles are tailored to the squad's goal — never generic. The role file you produce conforms to `templates/role-definition.md`, lives at `.claude/agents/<role-name>.md`, and is registered in `.squad/roster.json` by `squad-roster`.

## Preflight

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."*
2. Read `.squad/roster.json` if it exists. Note existing role names — your new role's name must not collide.
3. Note the squad's mode (`one-time`, `multi-use`, `evergreen`). It affects the `isolation` field decision below.

## Interactive flow — ask one question at a time

Do not batch questions. Wait for each answer before moving on.

### Q1 — What does this role do? (purpose)

Ask: *"What does this role do? One sentence, action-first."*

Examples of good answers:
- "Pull Klaviyo flow performance data via MCP and dump it as JSON"
- "Read the data, compute revenue impact estimates, rank fixes"
- "Take the ranked list and write the final report markdown"

If the answer is vague ("does everything", "handles the data"), push back: *"Narrower — what's the one artifact this role produces?"*

### Q2 — What's a good name? (kebab-case)

Propose a name derived from the purpose. Examples:
- "Pull Klaviyo data" → `klaviyo-data-puller`
- "Write the report" → `report-writer`
- "Scrape competitor pricing" → `competitor-scraper`

Ask: *"I'll call this role `<proposed>`. Override if you prefer something else."*

Check against `.squad/roster.json` for collisions. If collision, propose a numbered variant (`-2`) or ask the user for a new name.

### Q3 — What files does it own? (file_scope)

Ask: *"What file paths or glob patterns does this role own? Edit/Write inside them auto-approve. Bash auto-approves only for in-sandbox scaffolding (mkdir/touch/cp/ln inside the role's provisioned workspace); everything else prompts you."*

Examples:
- `reports/klaviyo/**, data/klaviyo/**`
- `src/auth/**, tests/auth/**`
- `intel/competitors/**`

Accept comma-separated globs. Validate that each is a sensible glob (no leading `/`, no absolute paths, no `..` traversal). If the user gives a too-broad scope (bare `**`, `*`, project root), warn: *"A bare `**` scope widens the PermissionRequest auto-approve surface to Edit/Write anywhere in the project — every in-scope write skips the prompt. Confirm or narrow."* Over-broad is allowed, but make it a conscious choice.

Scope-glob semantics the `PermissionRequest` hook enforces (so set expectations accordingly):
- `prefix/**` — the whole subtree under `prefix` (this is what you want for "owns this directory").
- A pattern with **no `/`** (e.g. `*.md`, `*.json`, `Makefile`) matches a **single path segment only** — i.e. files at the project root, never nested ones. If a role needs every `.md` under `reports/`, use `reports/**`, not `*.md`.
- Globs containing `/` match segment-for-segment — `*` never crosses a `/` (so `data/*` matches `data/x`, not `data/sub/x`). Use `prefix/**` for recursive ownership.
- `**` — everything (the too-broad case above).

### Q4 — What tools does it need?

Ask: *"What tools does this role need? Common picks: `Read, Write, Edit, Bash, Glob, Grep`. Add MCP tools like `mcp__claude_ai_Klaviyo__*` or `mcp__claude_ai_Shopify__*` if it uses external services. Read-only roles can drop `Write, Edit`."*

Validate against Claude Code's tool list (see [sub-agents doc](https://code.claude.com/docs/en/sub-agents#available-tools)). Note that `Agent`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`, and `WaitForMcpServers` are not available to subagents — strip them silently if listed.

If the user requests `Bash` alongside a broad `file_scope` (from Q3), note in one line: *"Bash defers to you except pure in-sandbox scaffolding when the role has a provisioned workspace — but a broad write scope plus Bash is a wide grant; keep the scope tight if you can."* Safe-by-default; just make it a conscious choice.

### Q5 — What model?

Ask: *"What model? `sonnet` (default — balanced), `haiku` (fast, cheap, for high-volume mechanical work), `opus` (deep reasoning, expensive), `fable` (the most capable model, for a role whose work is larger than a single sitting — it sustains long autonomous sessions, investigates before acting, and self-verifies; good for a long-running research or audit role), or `inherit` (match the parent session). A full model ID (e.g. `claude-opus-5`) also works if you want to pin a specific version."*

Default to `sonnet` if the user is unsure.

Only if this role's work is genuinely long-running or high-stakes — a research or audit role, a `fable` pick, or anything where reasoning depth changes the outcome — ask one follow-up: *"Reasoning effort for this role? Leave it inheriting the session's effort (default), or pin one of `low`, `medium`, `high`, `xhigh`, `max` — which tiers are available depends on the model (Fable 5, Opus 5, and Sonnet 5 support all five)."* Skip this follow-up otherwise — squad-role asks one question at a time and most roles don't need a second one here.

### Q6 — Worktree isolation? (skip in One-time mode if not relevant)

Only ask this in **One-time mode** if the role will edit files that other roles might also touch:

*"Should this role run in its own git worktree (isolated copy of the repo)? Yes if multiple roles in this squad might edit overlapping files; no otherwise."*

If yes: set `isolation: worktree` in the role's frontmatter.

In **Multi-use mode**, do not ask — `${CLAUDE_PLUGIN_ROOT}/skills/squad-spawn/scripts/spawn.sh` only pre-creates one git worktree per role (`git worktree add`) as an optional working directory; it does not launch teammates, and there is no `--worktree` teammate-launch flag. Teammate file isolation comes from each role's disjoint `file_scope`, not from this frontmatter field or any flag.

In **Evergreen mode**, do not ask — isolation is irrelevant for scheduled solo runs.

### Q7 — Does this role need a provisioned environment? (sandbox)

Most roles benefit from a sandbox — a private workspace dir with scaffolded folders, an env file, seeded reference material, and verified tools. Ask:

*"Should this role get a provisioned sandbox (a private `.squad/workspaces/<name>/` it works inside, with the reference material and tools it needs prepared up front)? Yes for most working roles; no for a trivial one-shot."*

If **yes**, hand off to `/cheeky-squad-os:squad-env` to derive the `environment` block from the role's purpose, role goal, `file_scope`, and tools — it sets `workspace`, `dirs`, `env`, `context`, and `tools`, and (importantly) adds `<workspace>/**` to this role's `file_scope` so the role's in-sandbox writes auto-approve. Substitute the canonical "Your workspace (sandbox)" section for `{{workspace_block}}`.

If **no**, omit `{{workspace_block}}` entirely and leave the `environment` field off the roster entry.

## Derive stop conditions (hard rule #14 — not a question, the flow does not grow)

Do not ask the user anything here. Once Q1–Q7 are answered, derive one thing from what you already have — it gets *written* to the role goal's `## Stop conditions` and *shown* in the Confirm block, never *asked*.

**2–4 bullets, each prefixed with exactly one of two verbs — never a bare bullet:**

- `needs:` — a **precondition**, checked before the role starts (mechanically: `squad-spawn`'s dispatch triage probes it at preflight, §3.4, and the role itself re-checks at the start of its own run). Must be mechanically checkable — file/path existence, a tool the role was given in Q4 being present, or one cheap read-only check. "The data looks reasonable" is not a `needs:` bullet; nothing runs against it, nothing fails it.
- `stop:` — a **mid-run bound** the role self-polices while working; there is no external monitor for it. Hitting it ends the run — the role writes `status: escalated` and `fired: <this bullet, verbatim>` on its own engagement record (the contract every generated role gets — see `{{stop_conditions_block}}` below) and stops.

Derive the mix from three sources, in this order, stopping once you have 2–4 total:

1. **The goal's Out of scope.** Read `## Out of scope` from `.squad/goal.md`. For every bullet that plausibly overlaps this role's purpose (Q1) or `file_scope` (Q3), add a `stop:` bullet: *"stop: the task would require `<out-of-scope item>` — excluded by the squad goal."*
2. **Purpose- and tool-specific edges.** From Q1's purpose and Q4's tools, name the one or two ways this specific role's work goes ambiguous or unsafe — a data-pulling role stops on empty/unauthorized results, a writing role stops on a contradiction between two sources it was handed, an MCP-heavy role gets a matching `needs:` (the MCP server is reachable) plus a `stop:` for that same tool returning an error or "not found" mid-run for something the task assumed existed. If Q7 gave this role a sandbox, add `needs: the provisioned workspace at <workspace> exists`.
3. **Two floor bullets, always available if 1–2 didn't reach the minimum of 2:** `needs: a required input this role depends on (data, prior hand-off, file) exists and is non-empty` and `stop: making progress would require writing outside this role's file_scope`.

Cap at 4 — pick the most concrete and likely, not every conceivable one. A condition that cannot be checked is not a condition ("if things get complicated" is a mood, not a bound); a condition that never fires in practice is noise the human has to read past.

## Compose the role's system prompt

Build the system prompt body from these answers. The template lives at `templates/role-definition.md`. Substitute **every** placeholder it defines — leaving any `{{...}}` unsubstituted produces a broken role (e.g. a literal `description: {{description}}` in frontmatter disables auto-delegation). Use the exact placeholder names from the template:

- `{{name}}` — role name (Q2)
- `{{description}}` — the auto-delegation trigger. **Not collected by a question — derive it** from Q1 purpose + the squad goal, phrased as a "Use when…" trigger (e.g. *"Use when the squad needs Klaviyo flow performance pulled and dumped as JSON"*). This is the `description:` frontmatter field Claude reads to decide when to delegate to this role.
- `{{purpose}}` — Q1 answer
- `{{tools}}` — Q4 answer
- `{{tools_rationale}}` — **derive** a one-line justification from the Q4 tools answer (why these tools, e.g. *"Read/Write/Bash to land JSON dumps; the Klaviyo MCP for the data pull"*).
- `{{model}}` — Q5 answer
- `{{effort_block}}` — the literal `effort: <tier>` line (Q5 follow-up), or omitted entirely if the user left it at the inherit-from-session default
- `{{file_scope_lines}}` — Q3 answer rendered as **one markdown bullet per glob** (not a comma-separated string — the template places it under a bullet list)
- `{{isolation_block}}` — the literal `isolation: worktree` line (Q6), or omitted entirely
- `{{workspace_block}}` — the "Your workspace (sandbox)" section (Q7), or omitted entirely if the role has no `environment` (canonical text in `squad-env`'s SKILL body)
- `{{plan_block}}` — the "Step 0 — publish your engagement record" section (hard rule #11). **Not collected by a question, and never omitted** — every generated role gets it, every time, regardless of mode or scope; it is a role-behavior contract, not a generation choice. Substitute the canonical text (same heading `templates/role-definition.md`'s placeholder legend names, and the same wording `squad-spawn` bakes into its spawn prompt — the standing role file and the per-dispatch prompt must not disagree):

  ```markdown
  ## Step 0 — publish your engagement record (hard rule #11)

  Before your first write to anything else, on every invocation, publish
  your engagement record to `.squad/role-plan-{{name}}.md`, using the
  schema in `templates/role-plan.md`: frontmatter `role: {{name}}`,
  `created: <ISO-8601>`, `status: active`; body sections in order —
  `## Task read`, `## Intended approach`, `## Deliverables`,
  `## Assumptions`, `## Amendments`. Grade every assumption `[confirmed]`,
  `[reported]`, `[inferred]`, or `[assumed]` — never a number — and for
  every `[assumed]` bullet, name what breaks: `if wrong → <deliverable or
  DoD signal>`. This path is granted unconditionally, before anything else —
  it is the bootstrap. Every other in-scope Edit/Write, your in-sandbox
  scaffolding Bash, and your own hand-off outbox all DEFER until it exists —
  the hook waits for you, it never denies you.
  ```

- `{{stop_conditions_block}}` — the "Your stop conditions" section (hard rules #14–#15). **Not collected by a question, and never omitted** — squad-role derives 2–4 stop conditions for every role (previous section), never zero, so this is on the same unconditional footing as `{{plan_block}}`. Substitute the canonical text (same wording `squad-spawn` bakes into its per-dispatch spawn prompt — the standing role file and the per-dispatch prompt must not disagree, same discipline as `{{plan_block}}`):

  ```markdown
  ## Your stop conditions (hard rules #14–#15)

  Your role goal (`{{role_goal_path}}`) declares this role's `## Stop
  conditions` — 2–4 bullets, each prefixed `needs:` (a precondition,
  checked before you start) or `stop:` (a mid-run bound you self-police;
  nothing external monitors it). If a `stop:` bound becomes true at any
  point during a run, do not guess forward and do not ask a question — a
  subagent has no reliable mid-run channel back to a human; your engagement
  record is the only hand-back there is. Instead:

  1. Update your own engagement record (`.squad/role-plan-{{name}}.md`) in
     place: set frontmatter `status: escalated` and `fired: <the bullet
     that fired, verbatim from ## Stop conditions>`.
  2. Fill three sections at the end of the record's body, exactly as
     `templates/role-plan.md` describes: `## What happened` (which
     condition fired, on what evidence, at which step of your `##
     Intended approach`), `## State of the work` (per declared
     deliverable: complete / partial: `<gap>` / untouched), and `## What
     would unblock` (the smallest grant, file, or ruling that would let
     you resume).
  3. Stop. Leave in place whatever deliverables you already finished —
     only the blocked one is left undone. Do not poll for a ruling, do
     not retry, do not add a fourth section.

  Never write `resolved`, `resolution:`, or anything that closes your own
  escalation, anywhere, on this or any file — that ruling belongs to the
  human alone, recorded later in `.squad/verification.md` by
  `/cheeky-squad-os:squad-verify`, never by you (hard rule #10). A role
  that could clear its own escalation could mint the verdict.
  ```

- **The belief-writing duty (hard rule #13).** **Not a `templates/role-definition.md` placeholder** — that template isn't touched by this feature, so there is no `{{...}}` token for it. Instead, insert the canonical text below directly into the composed body, immediately after `{{stop_conditions_block}}`'s substituted content and before the template's static `## Your file scope` heading. **Never omitted, never asked about** — same unconditional footing as `{{plan_block}}` and `{{stop_conditions_block}}`: every role can learn something durable about the domain regardless of purpose, and unlike those two, this duty is exercised mid-run rather than at dispatch, so it is never baked a second time into `squad-spawn`'s per-dispatch prompt — it lives here, in the standing role file, only. Substitute `{{name}}` with the role's own name, same as everywhere else in this composition. (Fenced with four backticks below because its own body contains a nested three-backtick example — don't collapse that to three or the inner fence breaks out early.)

  ````markdown
  ## Sharing what you learn (hard rule #13)

  When you learn something durable about the domain — not the task,
  `.squad/goal.md` already owns that — that another role, or a future run of
  this squad, would benefit from knowing, write it to your own claims file:
  `.squad/world/claims-{{name}}.md`. It's granted to you the same way your
  engagement record and outbox are — once your engagement record exists
  (hard rule #11); asserting a belief is acting.

  Use this belief block, one per fact:

  ```markdown
  ## Belief: <kebab-key>

  Claim: <one sentence, falsifiable>
  Source: <file, command, URL, tool read, or person>
  Grade: confirmed | reported | inferred | assumed
  Observed: <ISO-8601 date>
  Status: live
  Notes: <optional>
  ```

  `Claim`, `Source`, `Grade`, and `Observed` are all required — a block
  missing any of them never reaches a future prompt; `world.sh`'s parser
  drops it, not a request asking you nicely. Grade it with the exact same
  four evidence classes your engagement record uses (never a number) — one
  vocabulary across the plugin.

  Before writing a new key, check `.squad/world/claims-*.md` (or the world
  index baked into your spawn prompt, if one was) for an existing belief
  that already says what you're about to say — reuse it rather than minting
  a near-duplicate. Never edit another owner's claims file — the
  `PermissionRequest` hook grants you only `claims-{{name}}.md`, so a write
  to anyone else's defers to the user regardless of what you intend. If you
  believe something that contradicts an existing `live` belief, do not edit
  it: write your own counter-block under the same key, in your own file —
  two `live` blocks under one key from different owners *are* the dispute;
  you never write the word `disputed` yourself, and you never decide which
  side is right. If your work depends on a key the index shows as disputed,
  say in your engagement record's `## Assumptions` which side you used and
  why.

  This file is never cleared between dispatches — unlike your engagement
  record and the hand-off channel, what you write here accumulates for the
  life of the squad.
  ````

- `{{role_goal_path}}` — `.squad/role-goal-<name>.md`
- `{{created}}` — current UTC time in ISO-8601 (the same timestamp written to the roster entry and the role-goal frontmatter)

The body must include:
1. A statement of purpose (from Q1).
2. An instruction to read `.squad/goal.md` and `.squad/role-goal-<name>.md` on every invocation.
3. A clear file-scope statement (the role knows what it owns).
4. A reminder that the role is reusable as both subagent and Agent Teams teammate, with the propagation caveat (`skills` and `mcpServers` frontmatter do not propagate to teammates; `tools` and `model` do; body is appended).
5. A comment that the file is generated — edit if the role's needs evolve.
6. The engagement-record instruction (`{{plan_block}}`) — already unconditional per the substitution above; nothing further to add here.
7. The stop-condition contract (`{{stop_conditions_block}}`) — likewise already unconditional; nothing further to add here.
8. The belief-writing duty (the "Sharing what you learn" block above) — likewise already unconditional; nothing further to add here.

## Write role goal

Compose `.squad/role-goal-<name>.md`. It mirrors the squad goal structure but scoped to this role's slice. Derive it from:

- The squad goal (read from `.squad/goal.md`)
- The role's purpose (Q1)
- The role's file scope (Q3) — outputs land here

Schema:

```markdown
---
parent: .squad/goal.md
role: <name>
created: <ISO-8601>
---

# Role goal — <name>

<one paragraph: this role's contribution to the squad goal, framed as an outcome>

## Owned outputs

- <artifact 1 in file_scope>
- <artifact 2 in file_scope>

## Hand-offs

- <next role this role hands off to, if any>

## Stop conditions

<!-- Hard rule #14. 2-4 bullets, derived above from purpose + tools + the
     goal's Out of scope. Every bullet is prefixed needs: (a precondition,
     checked at squad-spawn's dispatch triage and again by the role at
     start) or stop: (a mid-run bound the role self-polices — no external
     monitor). When a stop: bound fires, the role writes status: escalated
     and fired: <the bullet, verbatim> on its own engagement record and
     hands back via templates/role-plan.md's three escalation sections — it
     never marks itself resolved; only the human's ruling in
     .squad/verification.md closes an escalation. Schema and full rationale:
     templates/role-goal.md. -->

- `needs:` <precondition>
- `stop:` <mid-run bound>
```

Write to `.squad/role-goal-<name>.md`. This mirrors `templates/role-goal.md`'s shape exactly — squad-role composes this schema directly rather than reading the template file at generation time, so if you ever touch this inlined copy, touch `templates/role-goal.md` to match (the two must not diverge).

## Write the role definition

Write the composed system prompt to `.claude/agents/<name>.md`. Use the YAML frontmatter from `templates/role-definition.md`.

## Register in roster

Call into `squad-roster` to add an entry for this role. The entry includes name, purpose, agent_file path, role_goal path, file_scope, tools, model, active flag (true), created timestamp, and — if the role got a sandbox in Q7 — the `environment` block. If the Q5 follow-up set a non-default effort tier, include `effort` too; if the user left it at inherit, omit the field entirely.

**Do not register `.squad/` contract paths in `file_scope`.** Since v0.4.1's `.squad/` structural reservation, the `PermissionRequest` hook grants a role three of its `.squad/` contract paths structurally, derived from its own `agent_type`, checked *before* `file_scope` is ever consulted for a `.squad/` path: its own engagement record, `.squad/role-plan-<name>.md` (hard rule #11, always granted — it's the bootstrap); its own hand-off outbox, `.squad/role-comm-<name>--*` (`templates/role-comm.md`, granted once the record exists); and its own belief-ledger claims file, `.squad/world/claims-<name>.md` (hard rule #13, granted the same way, once the record exists — asserting a belief is acting too). Registering any of these yourself in `file_scope` was the forgery hole v0.4.1 closed: a broad scope (`**`, `.squad/**`) would otherwise have matched them and auto-approved writes to another role's record, outbox, or claims file. So leave all three paths out of the `file_scope` you write to the roster entry — don't ask the user about them either; it's not a generation choice, it's how the hook derives the grant.

A roster generated before v0.4.1 that still lists one or more of these is harmless: the reservation is checked first, so `file_scope` never gets consulted for a `.squad/` path regardless of what it contains. No migration is needed, and there's nothing to "clean up" in an existing roster's `file_scope` unless the user asks.

## Confirm

Print to the user:

```
Role `<name>` generated.
  Purpose: <one line>
  Owns: <file_scope>
  Tools: <tools>
  Model: <model>
  Effort: <effort, if set>
  Stop conditions (hard rule #14): <n> declared
    - needs: <precondition 1>
    - stop: <mid-run bound 1>
    [...]
  Agent file: .claude/agents/<name>.md
  Role goal: .squad/role-goal-<name>.md
  Registered in: .squad/roster.json
```

The stop conditions are never asked for — they're derived (previous section) and shown here so the user sees them without a new question in the flow.

Then ask whether the user wants to generate another role (loop back to Q1 with a fresh name) or finish.

## Refusals

- **No squad goal:** refuse and point at `squad-onboard`.
- **Name collision:** ask for a different name; never overwrite an existing role file.
- **Empty purpose:** push back; do not write a role with a vague purpose.
- **Too-broad file scope:** warn but allow if user confirms.

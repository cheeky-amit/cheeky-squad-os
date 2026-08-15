---
name: squad-role
description: Use when the user wants to add a teammate to the squad — phrases like "generate a role", "add a teammate", "we need someone who…", "add a researcher/auditor/writer/analyst/scraper to the squad", "create a role for X". Also invoked by squad-onboard once per proposed role. Asks what the role does, owns, needs, and how deeply it reasons; writes the provider-neutral roster v2 entry and the current Claude role artifact.
license: MIT
---

# squad-role

You generate one bespoke role per invocation. Roles are tailored to the squad's goal — never generic. The provider-neutral role is registered in `.squad/roster.json` schema v2 by `squad-roster`. For the active Claude lifecycle, also render `templates/role-definition.md` to `.claude/agents/<role-name>.md`. Codex artifacts are compiled from the same canonical role during export; do not author a second Codex-specific roster.

## Roster shape compatibility

Whenever this skill reads `.squad/roster.json`, choose its source shape once:
`schema_version: 2` means v2; no schema version means legacy. Project roles into a
read-only lifecycle view using these equivalents:

- identifier: v2 `id` // legacy `name`
- cadence: v2 `execution_mode` // legacy `mode`
- goal references: `squad_goal_ref` in both shapes; v2 `goal_ref` // legacy `role_goal`
- ownership: v2 `file_ownership.include` and `.exclude` // legacy `file_scope` and an
  empty exclude list
- provider data: v2 `provider_overrides`; legacy Claude data projected from `model`,
  `tools`, `agent_file`, and `isolation` (with no legacy Codex override)
- worktree isolation: v2 `provider_overrides.claude.isolation` // legacy `isolation`

The `//` notation names source-shape equivalents; it is not permission to fall back to
legacy aliases inside a malformed v2 object. Validate the selected shape and stop on a
missing required field. This projection is read-only. Preserve a legacy roster's source
shape on ordinary lifecycle writes; migrate it to v2 only through a separate
`squad-roster` conversion plan that previews the exact writes/deletes and receives the
matching confirmation. If a requested change cannot be represented losslessly in legacy
shape, stop and offer that migration instead of dropping data.

## Preflight

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."*
2. Read `.squad/roster.json` if it exists. Canonicalize a legacy roster in memory through `squad-roster`; do not rewrite it merely because it is legacy. Note existing role IDs — the new role must not collide. **Count active roles (`active: true`).** If the count is already 5 (hard rule #16, `MAX_ACTIVE_ROLES`), refuse to start Q1: print the active roster (id + purpose, one line each) and suggest consolidating two roles into one or deactivating one via `squad-roster` first — *"A squad that needs a sixth seat needs a better decomposition, not a bigger roster."* Deactivated roles don't count toward the cap; an over-cap legacy roster (more than 5 active roles from before this rule existed) is grandfathered — it keeps working, but this refusal still blocks any *new* addition until the active count drops under 5.
3. Note the squad's mode (`one-time`, `multi-use`, `evergreen`). It affects the `isolation` field decision below.
4. If `.squad/world/claims-research.md` exists, read it. It holds domain-research findings the human gated during `squad-onboard` (Grade `confirmed` or `reported` only — `world.sh` rejects anything else from that file). Feed it into **Derive stop conditions** below. Absent file → this source is simply skipped; nothing about the rest of this flow changes. A squad that never ran research looks identical to one running a version of this plugin that never shipped the feature.
5. If `.squad/partner.md` exists, read it (hard rule #12). Its `## Decide vs. ask` section's "Always ask first" items feed **Derive stop conditions** below the same way belief-derived bounds do. Its `## Standing constraints` and `## Beliefs to check` are not a role-generation input here — `squad-onboard` already used Standing constraints to pre-populate the goal's Out of scope (which source 3 below already reads), and `squad-spawn` bakes the whole file into every dispatch prompt fresh each run (hard rule #4), so nothing from it needs to be captured into a standing role file at generation time. Absent file → this source is simply skipped, same as source 1 above; nothing else in this flow changes.

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

Accept comma-separated globs. Validate that each is a sensible glob (no leading `/`, no absolute paths, no `..` traversal). If the user gives a too-broad scope (bare `**`, `*`, project root), warn: *"A bare `**` scope widens the PermissionRequest auto-approve surface to Edit/Write anywhere in the project — every in-scope write skips the prompt. Confirm or narrow. One thing it can never reach regardless: `.squad/partner.md` (and every other `.squad/` path) — the hook's `.squad/` structural reservation is checked before `file_scope` is ever consulted, so this role could never auto-approve a write to the human's partner model, even with `**`."* Over-broad is allowed, but make it a conscious choice.

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

### Q8 — Skill onboarding

Not one question — a short sub-flow, run once per role, immediately after Q7 and before
stop conditions are derived. A role isn't just a prompt: it can carry **onboarded
skills**, external open-source skill files it researched, adapted, and had approved.
Rule of the flow: *don't reinvent the wheel — find an existing open-source skill first,
onboard it, and improve it; always keep attribution.*

1. **Research first — two dimensions, always both.** From Q1's purpose and the squad
   goal, research never stops at how the role *thinks* — it also covers how the role
   *acts*. Run both:
   - **(knowledge)** — frameworks, logic, domain best practice. Check, in this order:
     `anthropics/skills`, `addyosmani/agent-skills`, `msitarzewski/agency-agents`,
     `obra/superpowers`, then a WebSearch / repo-tree search for anything
     domain-specific to this role.
   - **(execution)** — how this role actually *performs* its actions on whatever
     platform(s) its purpose names: official APIs, MCP servers, CLIs, bulk/export
     mechanics, platform documentation. Check the same four curated repos first (an
     execution skill sometimes lives there too), then official platform docs and MCP
     server registries. A how-to skill distilled from official platform docs still
     counts as research-first — the docs are the source, and the resulting skill's
     `Source:` line attributes them like any other source.

   State plainly, **per dimension**, when nothing relevant turns up — only then author
   an original skill for that dimension. A role with no platform to operate skips the
   execution dimension outright (there's nothing to research) and says so explicitly,
   rather than silently running only the knowledge search.

2. **Propose.** Print a numbered list, one item per candidate, each one labeled
   `(knowledge)` or `(execution)`:
   - proposed skill name (kebab-case)
   - `(knowledge)` or `(execution)`
   - source — the URL, or `original`
   - one-line purpose
   - one line on what gets adapted or improved for this squad

   Mirror the research verb's Gate 1 UX (`squad-world`'s research-plan gate,
   `ARCHITECTURE.md`): accept the whole list in one word (`go`), skip skill onboarding
   for this role entirely in one word (`skip`), or edit — reword an item, drop one, add
   one — in the same reply.

3. **Approval gate.** Default is `approval_mode: user` — ask before onboarding each
   skill. Auto-approve (`approval_mode: auto`) only when one of two things is already
   true, never inferred mid-flow:
   - `.squad/partner.md` carries a standing constraint authorizing skill onboarding
     without asking (hard rule #12 — told, not inferred), or
   - `.squad/goal.md`'s frontmatter has `skill_onboarding: auto` (set once, during
     `squad-onboard`, when the builder said so)

   Record the mode and an ISO-8601 `approved_at` on every entry, whichever channel
   approved it. The same gate governs `squad-roster`'s Refresh-skills operation later —
   an upgrade proposed on refresh is still a proposal, never a silent swap.

4. **Onboard.** For each approved item: fetch the source, rewrite/adapt it into
   standard SKILL.md shape (YAML frontmatter `name`/`description`, then body), keep a
   `Source: <url>` attribution line near the top of the body (`Source: original` if
   authored fresh), and **end the body with a mandatory `## Provenance & limits`
   block** — this is a stated contract, not a courtesy: **an onboarded skill without
   this block is not onboarded**, and `squad-roster`'s Add operation refuses to
   register it (see that skill). Shape:

   ```markdown
   ## Provenance & limits

   Sources searched: <every source checked for this dimension, including the ones
   that came back empty — e.g. "anthropics/skills (no match), addyosmani/agent-skills
   (no match), msitarzewski/agency-agents (this skill, adapted), Klaviyo official API
   docs (execution mechanics)">
   Intake date: <ISO-8601>
   Known limits: <what this skill does NOT cover, or where it's likely shallow>
   Assumed superseded: this skill reflects what research found at intake, not the
   best way that exists. Re-run `squad-roster`'s Refresh-skills operation
   periodically rather than treating this as final.
   ```

   Write the finished file to `.squad/skills/<role-id>/<skill-name>/SKILL.md`. Append
   the entry to this role's `onboarded_skills` via `squad-roster` — do not hand-edit
   `roster.json` — and let `squad-roster` regenerate `roster.md`.

5. **Execution-gap check — not optional.** A role whose Q1 purpose names a specific
   platform, tool, or service it must *operate* (not just read about) may not close Q8
   with zero execution skills and nothing said about it. If step 1's execution
   dimension came back empty, or nothing from it got approved, Q8 is not finished until
   the gap is declared. Print exactly this shape:

   *"`<role-id>` operates `<platform/tool>`, but no execution skill was found or
   approved for it. Declaring this as a capability gap: `<one line — what's actually
   missing, e.g. "no MCP server connected for the Klaviyo bulk-send API">`. I can
   propose `<the fix — an MCP server to connect, a CLI to install>` for you to approve
   via `squad-env`."*

   Then, both of the following — neither is optional narration:
   - Write a `## Declared capability gaps` section to this role's role-goal file (see
     "Write role goal" below) — one bullet per gap, same shape as the printed line.
   - Hand the proposed fix to `squad-env`'s existing contain/propose channel
     (`global_needs`) — the same mechanism that already proposes a missing system CLI
     or MCP server; do not invent a second channel (see `squad-env`'s "How this
     composes with the rest of the squad").

   This check applies even when the user said `skip` at step 2: a platform-operating
   role that skipped Q8 entirely still gets a declared capability gap — there is
   obviously no execution skill — named plainly rather than silently absent.

If the user said `skip` at step 2 and the role doesn't operate a platform (so the
execution-gap check above never fires), none of this runs — the role registers with no
`onboarded_skills`, `{{onboarded_skills_block}}` is omitted for it, and it is
indistinguishable from a role generated before this feature shipped.

## Map answers to the canonical role

The interactive questions retain familiar Claude terms because the active lifecycle
still produces a Claude agent. Before registration, map them into roster v2:

- Q2 name → `id`.
- Q1 purpose → `purpose`; derive the “Use when…” trigger as `description`.
- Q3 `file_scope` → `file_ownership.include`; explicit denials →
  `file_ownership.exclude`.
- Q4 tools → portable `capabilities`, and preserve exact Claude tools in
  `provider_overrides.claude.tools`. Never guess an `external.mcp` mapping.
- Q5 model/effort → neutral reasoning profile/effort plus a Claude model override when
  the choice is provider-specific.
- Q7 sandbox → canonical `environment` (`dirs` becomes `directories`; `env` becomes
  `variables`). Values may contain non-secret provisioning configuration; credentials never
  belong in the roster, and export redacts all values from the portable snapshot.
- Q8 skill picks → `onboarded_skills` entries (`name`, `kind`: `knowledge` |
  `execution`, `source_url` — omitted for an original skill, `local_path`, `purpose`,
  `approval_mode`, optional `approved_at`).

The Claude agent path goes in `provider_overrides.claude.agent_file`. Do not add Codex
syntax here; the Codex adapter compiles from the canonical role at export time.

## Derive stop conditions (hard rule #14 — not a question, the flow does not grow)

Do not ask the user anything here. Once Q1–Q7 are answered, derive one thing from what you already have — it gets *written* to the role goal's `## Stop conditions` and *shown* in the Confirm block, never *asked*.

**2–4 bullets, each prefixed with exactly one of two verbs — never a bare bullet:**

- `needs:` — a **precondition**, checked before the role starts (mechanically: `squad-spawn`'s dispatch triage probes it at preflight, §3.4, and the role itself re-checks at the start of its own run). Must be mechanically checkable — file/path existence, a tool the role was given in Q4 being present, or one cheap read-only check. "The data looks reasonable" is not a `needs:` bullet; nothing runs against it, nothing fails it.
- `stop:` — a **mid-run bound** the role self-polices while working; there is no external monitor for it. Hitting it ends the run — the role writes `status: escalated` and `fired: <this bullet, verbatim>` on its own engagement record (the contract every generated role gets — see `{{stop_conditions_block}}` below) and stops.

Derive the mix from five sources, in this order, stopping once you have 2–4 total:

1. **Belief-derived bounds (only when `.squad/world/claims-research.md` exists — see Preflight step 4).** For every `confirmed` finding in that file whose claim plausibly constrains this role's purpose (Q1) or `file_scope` (Q3), add a `stop:` bullet naming the constraint the finding implies, citing the belief key so the bound is traceable: *"stop: `<the constraint>` — per `<belief-key>`."* Only `confirmed` findings earn a binding bound this way; a `reported` one is context the role can read, not a bound it self-polices — the human downgraded it to `reported` at Gate 2 precisely because it wasn't strong enough to bind. For every research question that came back **unanswered** and touches this role's purpose or scope, add a `needs:` bullet: *"needs: `<the question>` is answered before this role commits — unanswered by research."* `squad-spawn`'s dispatch triage can't mechanically resolve an open question, so this bullet doesn't block dispatch — it routes to the human at the triage step the same way any other non-checkable `needs:` does (the user may always dispatch anyway).
2. **Ask-first bounds (only when `.squad/partner.md`'s `## Decide vs. ask` exists — hard rule #12, see Preflight step 5).** For every item under "Always ask first" that plausibly overlaps this role's purpose (Q1) or `file_scope` (Q3), add a `stop:` bullet: *"stop: this task would require deciding `<the ask-first item>` — per `.squad/partner.md`, always ask first."* This is deliberately never a `needs:` bullet: an ask-first item isn't a precondition to check before the role starts, it's a bound the role can only discover it has hit mid-task — the role surfaces it rather than deciding (`squad-spawn`'s binding block carries the how), and this stop condition is what tells the role that surfacing, not guessing, is the correct move when it gets there. Be sparing: promoting an ask-first item to a declared bound means hitting it **ends the run** under hard rule #14, so reserve it for the one or two items where continuing past the unmade decision would waste the rest of the role's work. Every other ask-first item still reaches the human — `squad-spawn`'s binding block has the role surface it and carry on with what doesn't depend on it — it just doesn't stop the run.

   **Say where the line lands, for the same reason `squad-onboard` Step 3 does.** `.squad/partner.md` is gitignored by default; `.squad/role-goal-<role>.md` is **committed**. A bullet derived here copies a sentence the human wrote about themselves across that line, so it never happens invisibly: in the Confirm block, mark each partner-derived bullet inline — *"(from `.squad/partner.md`; `.squad/role-goal-<name>.md` is committed, that file is not — say the word and I'll drop it)"* — and drop any the user strikes. Paraphrase the ask-first item down to the decision it bounds rather than quoting a whole line of the human's brief where the shorter form still binds. Striking a bullet here is **never** an instruction to edit `.squad/partner.md`: this skill has no write access to it, and `squad-partner update` is the only path that ever changes it (hard rule #12).
3. **The goal's Out of scope.** Read `## Out of scope` from `.squad/goal.md`. For every bullet that plausibly overlaps this role's purpose (Q1) or `file_scope` (Q3), add a `stop:` bullet: *"stop: the task would require `<out-of-scope item>` — excluded by the squad goal."* (Note: if `.squad/partner.md`'s Standing constraints were folded into this Out of scope list at `squad-onboard`'s Step 3, a bullet sourced that way is indistinguishable from any other Out of scope bullet here — this source doesn't need to re-read `.squad/partner.md` itself for that half; it's already on the goal.)
4. **Purpose- and tool-specific edges.** From Q1's purpose and Q4's tools, name the one or two ways this specific role's work goes ambiguous or unsafe — a data-pulling role stops on empty/unauthorized results, a writing role stops on a contradiction between two sources it was handed, an MCP-heavy role gets a matching `needs:` (the MCP server is reachable) plus a `stop:` for that same tool returning an error or "not found" mid-run for something the task assumed existed. If Q7 gave this role a sandbox, add `needs: the provisioned workspace at <workspace> exists`.
5. **Two floor bullets, always available if 1–4 didn't reach the minimum of 2:** `needs: a required input this role depends on (data, prior hand-off, file) exists and is non-empty` and `stop: making progress would require writing outside this role's file_scope`.

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
- `{{onboarded_skills_block}}` — the "Onboarded skills" section (Q8), or omitted entirely if the role has no `onboarded_skills` entries. When present: one bullet per skill — name — `(knowledge|execution)` — absolute path to its `SKILL.md` — purpose — `Source: <url or "original">` — followed by the standing step-further check (canonical text below; same wording `squad-spawn` bakes into its per-dispatch prompt — the standing role file and the per-dispatch prompt must not disagree, same discipline as `{{plan_block}}` and `{{stop_conditions_block}}`):

  ```markdown
  Before executing, one step-further check: ask yourself — "could one more
  research step find a better way than my onboarded method?" If yes, and
  the step is cheap (one search, one doc lookup, one MCP introspection
  call — never a second research pass), take it. Record the answer either
  way in your engagement record's `## Assumptions` (hard rule #11):
  `[confirmed]` if you checked and your onboarded method still holds, or
  `[inferred]`/`[assumed]` with `if wrong → <what breaks>` if you took the
  step and found something better, or didn't check. Never spiral — one
  step, bounded, then proceed with whichever method you're using.
  ```
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

<!-- Hard rule #14. 2-4 bullets, derived above from confirmed/unanswered
     research findings (if any) + purpose + tools + the goal's Out of scope.
     Every bullet is prefixed needs: (a precondition,
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

## Declared capability gaps

<!-- Only present when Q8's execution-gap check fired (this role operates a
     platform and no execution skill was onboarded for it). Omit this whole
     heading otherwise — same absence contract as every other conditional
     section in this plugin. One bullet per gap, same shape as the printed
     refusal line. Cleared by squad-roster's Refresh-skills operation when
     a matching execution skill is later onboarded. -->

- <platform/tool this role can't yet operate — what's missing, and what was
  proposed via squad-env's global_needs to close it>
```

Write to `.squad/role-goal-<name>.md`. This mirrors `templates/role-goal.md`'s shape exactly — squad-role composes this schema directly rather than reading the template file at generation time, so if you ever touch this inlined copy, touch `templates/role-goal.md` to match (the two must not diverge).

## Write the role definition

Write the composed system prompt to `.claude/agents/<name>.md`. Use the YAML frontmatter from `templates/role-definition.md`.

## Register in roster

Call into `squad-roster` to add the canonical role. It includes `id`,
`purpose`, `description`, `file_ownership`, `capabilities`, `reasoning`, `active: true`,
`goal_ref`, the created timestamp, optional canonical `environment`, optional
`onboarded_skills` (Q8), and the exact Claude choices under `provider_overrides.claude`. A v2 roster stores that object directly.
For a legacy roster, `squad-roster` must preserve the legacy source shape with its
documented reverse projection and forward-projection check. If this role uses exclusions,
Codex overrides, or other v2-only semantics, stop and separately preview/confirm migration
before registration; never silently convert the whole roster or discard those semantics.

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
  Onboarded skills: <n> declared
    - <skill-name> (<knowledge|execution>, from <source_url or "original">)
    [...]
  Declared capability gaps: <n> (or "none")
    - <gap 1>
    [...]
  Agent file: .claude/agents/<name>.md
  Role goal: .squad/role-goal-<name>.md
  Registered in: .squad/roster.json
```

The stop conditions are never asked for — they're derived (previous section) and shown here so the user sees them without a new question in the flow. `Onboarded skills` reflects whatever Q8 produced — `0` if the role skipped Q8 or nothing was approved. `Declared capability gaps` reflects the execution-gap check — `none` unless this role operates a platform and closed Q8 without an execution skill for it.

**Then print the updated squad card** — both parts, text card and mermaid squad map, same canonical shape as `squad-onboard`'s "Narration — the squad card" section (see there for the exact node/edge shape and label-escaping rules; do not restate or redefine the shape here, just render it from the current roster). Covers the whole squad — every active role, not just the one just generated — each role's text-card row and map-node label carrying its own `skills onboarded: <n>` / `skills: <n>` count. This runs every time, whether this is the squad's first role or its fifth.

Then, unless the active count is now 5, ask whether the user wants to generate another role (loop back to Q1 with a fresh name) or finish. **If the active count is now 5, skip that offer** — print instead: *"Squad is at the 5-seat cap — deactivate or consolidate a role via `squad-roster` before generating another."*

## Refusals

- **No squad goal:** refuse and point at `squad-onboard`.
- **Name collision:** ask for a different name; never overwrite an existing role file.
- **Empty purpose:** push back; do not write a role with a vague purpose.
- **Too-broad file scope:** warn but allow if user confirms.

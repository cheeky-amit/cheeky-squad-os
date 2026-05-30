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

Ask: *"What file paths or glob patterns does this role own? Edit/Write inside them are auto-approved; everything else — including Bash, in v1 — prompts you."*

Examples:
- `reports/klaviyo/**, data/klaviyo/**`
- `src/auth/**, tests/auth/**`
- `intel/competitors/**`

Accept comma-separated globs. Validate that each is a sensible glob (no leading `/`, no absolute paths, no `..` traversal). If the user gives a too-broad scope (`**`, `*`, project root), warn: *"That scope auto-approves writes anywhere in the project. Confirm or narrow."*

Scope-glob semantics the `PermissionRequest` hook enforces (so set expectations accordingly):
- `prefix/**` — the whole subtree under `prefix` (this is what you want for "owns this directory").
- A pattern with **no `/`** (e.g. `*.md`, `*.json`, `Makefile`) matches a **single path segment only** — i.e. files at the project root, never nested ones. If a role needs every `.md` under `reports/`, use `reports/**`, not `*.md`.
- `**` — everything (the too-broad case above).

### Q4 — What tools does it need?

Ask: *"What tools does this role need? Common picks: `Read, Write, Edit, Bash, Glob, Grep`. Add MCP tools like `mcp__claude_ai_Klaviyo__*` or `mcp__claude_ai_Shopify__*` if it uses external services. Read-only roles can drop `Write, Edit`."*

Validate against Claude Code's tool list (see [sub-agents doc](https://code.claude.com/docs/en/sub-agents#available-tools)). Note that `Agent`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`, and `WaitForMcpServers` are not available to subagents — strip them silently if listed.

### Q5 — What model?

Ask: *"What model? `sonnet` (default — balanced), `haiku` (fast, cheap, for high-volume mechanical work), `opus` (deep reasoning, expensive), or `inherit` (match the parent session)."*

Default to `sonnet` if the user is unsure.

### Q6 — Worktree isolation? (skip in One-time mode if not relevant)

Only ask this in **One-time mode** if the role will edit files that other roles might also touch:

*"Should this role run in its own git worktree (isolated copy of the repo)? Yes if multiple roles in this squad might edit overlapping files; no otherwise."*

If yes: set `isolation: worktree` in the role's frontmatter.

In **Multi-use mode**, do not ask — per-teammate `--worktree` is enforced by `scripts/spawn.sh` (the CLI flag, not the frontmatter field).

In **Evergreen mode**, do not ask — isolation is irrelevant for scheduled solo runs.

## Compose the role's system prompt

Build the system prompt body from these answers. The template lives at `templates/role-definition.md`. Substitute **every** placeholder it defines — leaving any `{{...}}` unsubstituted produces a broken role (e.g. a literal `description: {{description}}` in frontmatter disables auto-delegation). Use the exact placeholder names from the template:

- `{{name}}` — role name (Q2)
- `{{description}}` — the auto-delegation trigger. **Not collected by a question — derive it** from Q1 purpose + the squad goal, phrased as a "Use when…" trigger (e.g. *"Use when the squad needs Klaviyo flow performance pulled and dumped as JSON"*). This is the `description:` frontmatter field Claude reads to decide when to delegate to this role.
- `{{purpose}}` — Q1 answer
- `{{tools}}` — Q4 answer
- `{{tools_rationale}}` — **derive** a one-line justification from the Q4 tools answer (why these tools, e.g. *"Read/Write/Bash to land JSON dumps; the Klaviyo MCP for the data pull"*).
- `{{model}}` — Q5 answer
- `{{file_scope_lines}}` — Q3 answer rendered as **one markdown bullet per glob** (not a comma-separated string — the template places it under a bullet list)
- `{{isolation_block}}` — the literal `isolation: worktree` line (Q6), or omitted entirely
- `{{role_goal_path}}` — `.squad/role-goal-<name>.md`
- `{{created}}` — current UTC time in ISO-8601 (the same timestamp written to the roster entry and the role-goal frontmatter)

The body must include:
1. A statement of purpose (from Q1).
2. An instruction to read `.squad/goal.md` and `.squad/role-goal-<name>.md` on every invocation.
3. A clear file-scope statement (the role knows what it owns).
4. A reminder that the role is reusable as both subagent and Agent Teams teammate, with the propagation caveat (`skills` and `mcpServers` frontmatter do not propagate to teammates; `tools` and `model` do; body is appended).
5. A comment that the file is generated — edit if the role's needs evolve.

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
```

Write to `.squad/role-goal-<name>.md`.

## Write the role definition

Write the composed system prompt to `.claude/agents/<name>.md`. Use the YAML frontmatter from `templates/role-definition.md`.

## Register in roster

Call into `squad-roster` to add an entry for this role. The entry includes name, purpose, agent_file path, role_goal path, file_scope, tools, model, active flag (true), and created timestamp.

## Confirm

Print to the user:

```
Role `<name>` generated.
  Purpose: <one line>
  Owns: <file_scope>
  Tools: <tools>
  Model: <model>
  Agent file: .claude/agents/<name>.md
  Role goal: .squad/role-goal-<name>.md
  Registered in: .squad/roster.json
```

Then ask whether the user wants to generate another role (loop back to Q1 with a fresh name) or finish.

## Refusals

- **No squad goal:** refuse and point at `squad-onboard`.
- **Name collision:** ask for a different name; never overwrite an existing role file.
- **Empty purpose:** push back; do not write a role with a vague purpose.
- **Too-broad file scope:** warn but allow if user confirms.

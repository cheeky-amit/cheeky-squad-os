# cheeky-squad-os — Architecture

## The pill

All Claude Code work — engineering, operational, agentic business infrastructure, knowledge work — goes better when you treat your AI session like a team with roles, responsibilities, communication, and supervision.

cheeky-squad-os ships the discipline, not the team. Your goal generates the team. Every squad is bespoke to the goal that spawned it.

This means the plugin contains **zero opinionated role files**. No `frontend-dev`. No `backend-dev`. No defaults. The role generator builds what each goal needs. A Klaviyo lifecycle audit needs different roles than a homepage redesign needs different roles than a weekly competitive intel loop. The framework is domain-neutral.

## What the plugin contains (and does not)

| Component | Ships in plugin | Generated per goal | Notes |
| --- | --- | --- | --- |
| Skills (6) | Yes | — | `squad-onboard`, `squad-goal`, `squad-role`, `squad-spawn`, `squad-roster`, `squad-env` |
| Hooks (3) | Yes | — | `SessionStart`, `UserPromptSubmit`, `PermissionRequest` |
| Templates (4) | Yes | — | `goal.md`, `role-goal.md`, `role-definition.md`, `roster.json` |
| Role files | **No — zero** | Yes, by `squad-role` | Written to `.claude/agents/<role-name>.md` in the user's project |
| Squad goal | — | Yes, by `squad-onboard` | `.squad/goal.md` |
| Role goals | — | Yes, by `squad-role` | `.squad/role-goal-<role-name>.md` per role |
| Roster | — | Yes, by `squad-roster` | `.squad/roster.json` (source of truth) |
| Role environment | — | Yes, by `squad-env` | Optional `environment` block per roster role; materialized as a sandbox under `.squad/workspaces/<role>/` by `provision.sh` |

The plugin is **discipline**. Everything else is **generated** from the user's goal.

## Hard rules

These are the load-bearing invariants the rest of the document references by number. Every skill, hook, and script upholds them.

1. **One north-star.** `.squad/goal.md` is the single binding outcome; every action a squad takes must serve it.
2. **No worker without the goal in scope.** No session, teammate, or subagent begins work without the squad goal present in its context. The `SessionStart` hook enforces this for sessions and teammates; `squad-spawn` enforces it for subagents by prompt-baking (see rule #4).
3. **Bespoke roles only.** The plugin ships zero default role files. Every role is generated to fit the goal.
4. **Prompt-baking is the only reliable parent→worker channel.** The full text of `.squad/goal.md` and the relevant `.squad/role-goal-<role>.md` is baked into every spawn prompt. `SessionStart` does not fire for subagents, so the baked prompt — not hook injection — is what guarantees a subagent sees its goal.
5. **Explicit file scope.** Each role declares a `file_scope`; the `PermissionRequest` hook auto-approves in-scope Edit/Write and defers everything else to the user.
6. **Mode controls cadence, not size.** One-time / Multi-use / Evergreen set persistence and dispatch primitive; squad size is set by goal decomposition.
7. **Per-role file isolation.** Roles are given disjoint `file_scope` so concurrent workers don't overwrite each other (agent-teams doc: "each teammate owns a different set of files"). One-time subagents may additionally set `isolation: worktree`; Multi-use can pre-create per-role worktrees via `skills/squad-spawn/scripts/spawn.sh` as working directories.
8. **Sandbox-scoped autonomy.** A role's `environment` (optional) is materialized as a sandbox — a filesystem-and-PATH boundary (`.squad/workspaces/<role>/` + a role-local `bin/` + a sourced `env` file). Inside it, the role provisions and works freely: the `PermissionRequest` hook auto-approves in-sandbox scaffolding (`mkdir`/`touch`/`cp`/`ln` with every operand inside the workspace) exactly as it auto-approves in-`file_scope` Edit/Write. The boundary is enforced by the same hook, not by a confirmation prompt.
9. **Propose what can't be contained.** Anything inherently global — a system CLI, an MCP server, a network fetch, an experimental/global flag — is never run by the provisioner. It is collected into `global_needs` and proposed to the user for approval. The escape hatch is not separate logic: "not in the sandbox vocabulary" is exactly what the hook already defers, and what `provision.sh` already refuses to execute.

## The three modes

Mode is inferred from goal language by `squad-onboard`. User can override. Agent count is decoupled from mode — squad size is determined by goal decomposition and domain expertise required.

| Mode | Cadence | Primitive | Example goal shape |
| --- | --- | --- | --- |
| **One-time** | Single bounded push | Subagents (stable; optional `isolation: worktree` per subagent). For large fan-outs or when adversarial cross-checking adds value, an optional **dynamic Workflow** runtime (see ["Dynamic Workflows"](#dynamic-workflows--where-they-fit-and-where-they-dont) below). | "deliver ranked Klaviyo lifecycle fix list with revenue impact estimates within one week" |
| **Multi-use** | Ongoing build over multiple workstreams | Agent Teams (experimental, env-gated). Teammate file isolation via **disjoint per-role `file_scope`**; `skills/squad-spawn/scripts/spawn.sh` optionally pre-creates one worktree per role as a working directory (it does not launch teammates). | "ship new homepage that converts at >5% by end of sprint" |
| **Evergreen** | Recurring, scheduled | `/loop` (in-session, 7-day max per `CronCreate` recurring-task expiry) **or** user-managed Routine / Desktop scheduled task (durable, configured by the user — plugin cannot create on their behalf) | "every Monday produce a 1-page competitor movement summary" |

Mode controls **cadence and persistence**. Agent count is set by the goal decomposition (how many parallel workstreams) and the domain expertise required (how many specializations).

## The six skills

Every skill ships as `skills/<name>/SKILL.md` with YAML frontmatter conforming to the agentskills.io open spec. Claude-Code-specific behaviors live in companion scripts (e.g. `skills/squad-spawn/scripts/spawn.sh`, `skills/squad-env/scripts/provision.sh`) or are gracefully degraded.

### 1. `squad-onboard`

**Trigger:** "I want to build…", "I need to ship…", "help me set up a weekly…", "audit this…", "do you have a goal?", first invocation in a project with no `.squad/`.

**Contract:**
1. Ask the one question: *"Do you have a goal?"*
2. Reformulate the user's answer into a measurable, time-bounded outcome (not an ask). Confirm before saving.
3. Infer mode (one-time / multi-use / evergreen) from goal shape — not asked. User can override.
4. Decompose the goal into parallel workstreams.
5. Propose role-need analysis: how many roles, what kinds. Hand off to `squad-role` for each.
6. Walk through permissions and any Agent Teams enablement needed.

**Writes:** `.squad/goal.md` (via `squad-goal`).

### 2. `squad-goal`

**Trigger:** "set the squad goal", "change the goal", "what's our goal", "show the goal".

**Contract:**
- Owns `.squad/goal.md` as the binding north-star constraint.
- Reads, writes, replaces, prints.
- Refuses to delete without confirmation.
- Used by `squad-onboard` (write at end of flow) and by `squad-spawn` (read before every spawn).

**Schema of `.squad/goal.md`:**
```markdown
---
mode: one-time | multi-use | evergreen
created: <ISO-8601 date>
target: <ISO-8601 deadline or "ongoing">
---

# Squad goal

<one outcome-framed paragraph, measurable, time-bounded>

## Definition of done

- <observable signal 1>
- <observable signal 2>
- <observable signal 3>

## Out of scope

- <explicit exclusions>
```

### 3. `squad-role`

**Trigger:** "generate a role", "add a teammate", "we need someone who…", invoked by `squad-onboard` for each proposed role.

**Contract:** Interactive flow per role:
1. *What does this role do?* (one-sentence purpose)
2. *What files does it own?* (glob patterns — drives `PermissionRequest` auto-approval)
3. *What tools does it need?* (allowlist for subagent frontmatter)
4. *What model is appropriate?* (`sonnet`, `opus`, `haiku`, or `inherit`)
5. *What scope does it own?* (workstream description, used to derive role goal)

Writes:
- `.claude/agents/<role-name>.md` — subagent definition using `templates/role-definition.md` schema
- `.squad/role-goal-<role-name>.md` — role goal derived from squad goal
- Registers entry in `.squad/roster.json` (via `squad-roster`)

**Output location note:** The original brief named `agents/<role-name>.md`. Claude Code scans `.claude/agents/` for project subagents (and `~/.claude/agents/` for user subagents), per [sub-agents doc](https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope). We use `.claude/agents/` so generated roles are discoverable without extra configuration.

### 4. `squad-spawn`

**Trigger:** "dispatch the squad", "spawn the team", "start the work", invoked by `squad-onboard` at end of onboarding.

**Contract:** Branches on mode.

```
Read .squad/goal.md  →  refuse if missing
Read .squad/roster.json  →  refuse if empty
Read .squad/role-goal-<role>.md for each active role

Switch on goal.mode:

  one-time:
    For each role: spawn subagent via Agent tool
    Spawn prompt = full text of goal.md + role-goal text + task description
    Subagents run sequentially or in parallel (orchestrator decides)
    If a generated role's .claude/agents/<role>.md sets `isolation: worktree`
      in its frontmatter, the subagent runs in a temporary git worktree
      (per sub-agents doc — frontmatter mechanism applies to subagents only,
      not to teammates).

  multi-use:
    Check $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
      Set to "1":
        Optionally invoke `skills/squad-spawn/scripts/spawn.sh` (it ONLY
        pre-creates one git worktree per active role under
        .claude/worktrees/<role>/ and emits
        JSON; it launches nothing and bakes no prompt). Then, as the team
        lead, orchestrate the Agent Team:
          - For each role, spawn a teammate referencing the subagent
            definition at .claude/agents/<role>.md by name (teammates are
            spawned by the lead in natural language — there is no
            `--worktree <role>` teammate-launch flag; that flag only starts
            standalone interactive sessions per the worktrees doc).
          - Enforce file isolation (hard rule #7) via disjoint per-role
            `file_scope` (agent-teams doc: "break the work so each teammate
            owns a different set of files"). If you want a teammate to work
            inside its pre-created worktree, point it there explicitly using
            the path from spawn.sh's JSON — nothing wires that automatically.
          - Spawn prompt = goal.md + role-goal text + task description
            (hard rule #4 — the only reliable context channel)
        Note (per agent-teams doc): when a subagent definition is used as
          a teammate, `skills` and `mcpServers` frontmatter do not
          propagate; `tools` and `model` do; body is appended to the
          teammate's system prompt as additional instructions.
      Not set:
        Explain what Agent Teams adds (shared task list, mailbox, direct
          teammate-to-teammate messaging) and why it's experimental.
        Offer to write {"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}
          into ~/.claude/settings.json (with explicit consent in the same turn).
        If user accepts: write the setting; instruct user to restart Claude
          Code; resume on next session.
        If user declines: fall back to sequential subagents (One-time path)
          with a clear printed warning that mailbox / shared-task-list
          features are unavailable.

  evergreen:
    The plugin cannot create durable scheduled work on the user's behalf.
    It sets up the goal and roles, then surfaces three options for the
    user to choose, printing exact commands or steps for each:

    Option A — /loop (in-session, 7-day max):
      Print the exact slash command for the user to run, of the form:
        /loop <interval> <command-or-prompt>
      The recurring task lives in the current session, fires at the
      chosen interval, and auto-expires 7 days after creation
      (per scheduled-tasks doc). Requires the session to be open.

    Option B — Cloud Routine (durable, Anthropic-managed):
      The user creates this themselves. The plugin prints the steps to
      configure a routine via the user's Claude Code routines surface
      (CLI or dashboard, depending on the user's version). The plugin
      does NOT call any "schedule" tool — it instructs and confirms.

    Option C — Desktop scheduled task (durable, local):
      The plugin prints the steps for the user to configure a scheduled
      task in the Claude Code desktop app, with the squad goal and
      first-role spawn command pre-formatted for copy-paste.
```

**Hard rule #4:** the full text of `.squad/goal.md` and the relevant `.squad/role-goal-<role>.md` MUST be injected into every spawn prompt — that is the only channel of context from parent to subagent/teammate.

### 5. `squad-roster`

**Trigger:** "show the roster", "who's on the squad", "remove <role>", "what does <role> own".

**Contract:**
- Manages `.squad/roster.json` (source of truth, JSON for tooling)
- Auto-generates `.squad/roster.md` for human reading (regenerated on each write)
- Used by `squad-role` to register roles, by `squad-spawn` to enumerate active teammates, and by the `PermissionRequest` hook to look up scope rules

**Schema of `.squad/roster.json`:**
```json
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "one-time | multi-use | evergreen",
  "created": "<ISO-8601>",
  "roles": [
    {
      "name": "klaviyo-data-puller",
      "purpose": "Extract flow performance, list health, deliverability from Klaviyo MCP",
      "agent_file": ".claude/agents/klaviyo-data-puller.md",
      "role_goal": ".squad/role-goal-klaviyo-data-puller.md",
      "file_scope": ["reports/klaviyo/**", "data/klaviyo/**"],
      "tools": ["Read", "Write", "Bash", "mcp__claude_ai_Klaviyo__*"],
      "model": "sonnet",
      "active": true,
      "created": "<ISO-8601>"
    }
  ]
}
```

### 6. `squad-env`

**Trigger:** "set up the workspaces", "provision the environments", "build each role's sandbox", "prepare the squad to run"; invoked by `squad-role` to derive a role's environment and by `squad-spawn` before dispatch.

**Contract:** Derives and materializes a per-role **sandbox** — the role's "ideal environment for operation," generated from the goal + role goal + `file_scope` + tools.

```
Read .squad/goal.md           →  refuse if missing
Read .squad/roster.json       →  refuse if no active roles

For each active role lacking an `environment`:
  Derive { workspace, dirs, env, context, tools } from the role goal + scope + tools
  Ensure <workspace>/** is in the role's file_scope (via squad-roster)

Run skills/squad-env/scripts/provision.sh (dry):
  Materialize (contained, run locally):
    - workspace dir + scaffolded `dirs` + role-local bin/
    - env file (SOURCED, never exported globally)
    - context (kind copy|link from in-project paths)
  Verify tools; classify the misses:
    - kind local + install targeting the sandbox  → local_plan (install INTO sandbox)
    - kind system | mcp | a network fetch         → global_needs (PROPOSE, never run)

Present the report; then:
  local_plan  → re-run provision.sh --install (one batch, contained autonomy)
  global_needs → print exact commands, ask the user (never run them)
```

**Writes:** the `environment` block into each role's `.squad/roster.json` entry (via `squad-roster`); the materialized sandbox under `.squad/workspaces/<role>/` (gitignored — the spec in `roster.json` is the committed source of truth).

**The sandbox is a filesystem-and-PATH boundary, not a kernel jail.** What it can contain: dirs, a sourced env file, a local tool prefix on `PATH`, locally-copied reference material. What it cannot contain — and therefore proposes — system packages, MCP servers, network fetches, and global/experimental flags. This split is hard rules #8 and #9.

## The role-definition template (no shipped roles — why)

Shipping default roles (`frontend-dev`, `backend-dev`, `qa-engineer`, etc.) is the trap. Defaults bias every goal toward the shape the defaults assume. A Klaviyo lifecycle audit doesn't need a `backend-dev` — it needs an `audit-researcher`, a `compliance-checker`, and a `report-writer`. A weekly competitive intel loop doesn't need any of those — it needs a `scraper`, an `analyst`, and a `summariser`.

The plugin ships the **template** (`templates/role-definition.md`) — the schema that `squad-role` fills in. Every role the generator ever writes derives from that one file.

The template's frontmatter conforms to Claude Code's subagent spec (see [sub-agents](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)):

```yaml
---
name: <role-name>                # lowercase, hyphenated
description: <when to delegate>  # used by Claude for auto-delegation
tools: <comma-separated>         # allowlist
model: sonnet | opus | haiku | inherit
isolation: worktree              # set when mode is multi-use; omitted otherwise
---
```

The body (system prompt) is composed by `squad-role` from the interactive answers, and includes an embedded reference to the role's goal file so the role sees its own goal on every invocation.

**Reusability note in every generated role file:** the role file works as both a subagent (via Agent tool) and as an Agent Teams teammate definition. When used as a teammate, the `skills` and `mcpServers` frontmatter fields do not propagate (per [agent-teams docs](https://code.claude.com/docs/en/agent-teams#use-subagent-definitions-for-teammates)); `tools` and `model` do; body becomes additional system prompt.

## The three hooks

Hooks provide **mechanical enforcement** — markdown rules in skills are aspirational; hooks are real. All three are registered in `plugin.json` so they install automatically.

### `SessionStart`

**Trigger:** Every new Claude Code session — `startup`, `resume`, `clear`, `compact` per [hooks doc](https://code.claude.com/docs/en/hooks). Per agent-teams doc, each Agent Teams teammate is "a separate Claude Code instance" that "loads the same project context as a regular session", so SessionStart fires for teammates too. Per sub-agents doc, **subagents are not separate sessions** — they receive a Task delegation message instead, and SessionStart does **not** fire for them. Their lifecycle event is `SubagentStart` (which fires in the parent session, not in the subagent's context).

**Script:** `hooks/session-start.sh`

**Behavior:**
- If `.squad/goal.md` exists: read it, return it in `hookSpecificOutput.additionalContext` so the goal is injected into the session's working context automatically.
- If `.squad/goal.md` does not exist: return a one-line notice — *"no squad goal set — run /cheeky-squad-os:squad-onboard"* — also via `additionalContext`.
- Always exit 0 (never block session start).

**Goal injection has two distinct mechanisms** (hard rule #4):
1. **Main session + Agent Teams teammates:** SessionStart hook injects goal via `additionalContext`. Automatic; user does not have to remember.
2. **Subagents (One-time mode and fallback path):** SessionStart does not fire. `squad-spawn` bakes the full text of `.squad/goal.md` and the relevant `.squad/role-goal-<role>.md` into the Task prompt string. This is the only reliable context channel from parent to subagent.

Both mechanisms produce the same end state — the worker sees the goal. They differ in *how* the goal gets there.

**Why it matters:** Hard rule #2 — no session starts without a goal in scope. For sessions and teammates the hook enforces it; for subagents `squad-spawn` enforces it via prompt-baking.

### `UserPromptSubmit`

**Trigger:** Every user turn ([hooks doc](https://code.claude.com/docs/en/hooks#userpromptsubmit)).

**Script:** `hooks/user-prompt-submit.sh`

**Behavior:**
- Read prompt from stdin.
- Read `.squad/goal.md` if it exists.
- Append a one-line context tag: `[squad goal in scope: <first 80 chars of goal>]` via `hookSpecificOutput.additionalContext`.
- **Do not block in v1.** Drift detection is a future feature; v1 is observational only.

**Why it matters:** The goal stays present in the model's working memory turn by turn, not just at session start. Drift becomes visible without being punishing.

### `PermissionRequest`

**Trigger:** Permission dialog about to appear for `Bash`, `Edit`, `Write` ([hooks doc](https://code.claude.com/docs/en/hooks)). The hook *fires* for all three (the `plugin.json` matcher is `Bash|Edit|Write`) and auto-approves on **two narrow surfaces**, deferring everything else to the user:

1. **`Edit`/`Write`** to a file inside the role's `file_scope`.
2. **`Bash`** that is pure in-sandbox scaffolding — verb in `{mkdir, touch, cp, ln}`, every path operand resolving inside the role's `environment.workspace`, and no shell metacharacter (so containment is provable). This is hard rule #8 — the role working freely inside its sandbox.

Both surfaces share the same containment primitives (normalize-to-relative, reject `..` traversal, fail-closed on doubt). Destructive verbs, installs, network, and any operand outside the workspace are **not** on the Bash list by design — they are the provisioner's "propose to the user" path (hard rule #9), not the running role's. A role with no `environment.workspace` gets no Bash auto-approval at all.

**Script:** `hooks/permission-request.sh`

**Behavior:**
- Parse the request JSON from stdin. Common input fields available across all hook events (per hooks doc) include `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`, plus the optional `agent_id` and `agent_type` (the latter is present "when inside subagent" per hooks doc). Tool-related events additionally include `tool_name`, `tool_input`, `tool_use_id`.
- Read `.squad/roster.json`.
- Determine the active role:
  - **If `agent_type` is set on the hook input:** it identifies the active subagent. Per sub-agents doc, the subagent's frontmatter `name` value is what the hook receives as `agent_type`. Match this against the `roles[].name` entries in `roster.json` to find the role's `file_scope`.
  - **If `agent_type` is absent:** the call is from the main session. Skip auto-approval and defer to the user (no decision returned).
- Check if the requested file path matches the role's `file_scope` glob patterns.
- If match: return `{decision: {behavior: "allow"}}` via `hookSpecificOutput`.
- If no match: omit decision so normal permission flow runs (user prompted).
- For a `Bash` call, look up the role's `environment.workspace` instead of `file_scope`: reject any shell metacharacter, require a scaffolding verb, and require every path operand to resolve inside the workspace — else defer.
- Fail-safe: any error path exits 0 with no decision so user is prompted (never silently allowed).

**Field confirmed:** `agent_type` is the correct identifier per both hooks doc (common input schema) and sub-agents doc ("Hooks receive this value as `agent_type`"). Not `subagent_type`, not `agent_name`, not `subagent_name`.

**Why it matters:** Roles have file scope. The hook mechanically enforces it. A role that owns `reports/**` won't blast `src/**` even if it tries — and the user gets prompted, not auto-denied, so they can override case-by-case.

## Data files

All squad state lives under `.squad/` in the user's project. Generated role definitions live under `.claude/agents/` (so Claude Code's subagent scanner finds them).

```
<user-project>/
├── .squad/
│   ├── goal.md                          # squad-onboard writes; squad-goal owns
│   ├── role-goal-<role-name>.md         # squad-role writes one per role
│   ├── roster.json                      # squad-roster owns (source of truth)
│   ├── roster.md                        # squad-roster auto-generates (human view)
│   └── workspaces/                      # provision.sh materializes one sandbox per role
│       └── <role-name>/                 #   (gitignored, ephemeral — spec lives in roster.json)
│           ├── bin/                     #   role-local tools, prepended to PATH by env
│           ├── env                      #   sourced, never exported globally
│           ├── inputs/ outputs/ …       #   scaffolded `dirs`
│           └── .provisioned.json        #   receipt
└── .claude/
    ├── agents/
    │   ├── <role-name-1>.md             # squad-role writes; Claude Code scans
    │   ├── <role-name-2>.md
    │   └── …
    └── worktrees/                       # spawn.sh pre-creates one per active role
        └── <role-name>/                 #   (Multi-use only; gitignored, ephemeral)
```

Schemas for `goal.md` and `roster.json` are above. `role-goal-<role-name>.md` mirrors `goal.md` structure but scoped to one role's slice of the squad goal.

### Version control

`.squad/` mixes shared squad state with ephemeral working artifacts. The plugin's shipped `.gitignore` (Phase 7) draws the line as follows:

| Path | Status | Why |
| --- | --- | --- |
| `.squad/goal.md` | **Commit** | The north-star outcome — the most important artifact in the repo. |
| `.squad/roster.json` | **Commit** | Source of truth for who's on the squad; needs to travel with the project. |
| `.squad/roster.md` | **Commit** | Auto-generated human view; committed for diff readability. |
| `.squad/role-goal-*.md` | **Commit** | Per-role goals — derived from squad goal but stable artifacts. |
| `.squad/workspaces/<role>/` | **Gitignore** | Per-role sandboxes materialized by `provision.sh`; ephemeral, recreated on each provision. The `environment` spec in `roster.json` is the committed source of truth. |
| `.squad/role-comm-*` | **Gitignore** | Inter-role communication scratch (reserved namespace; v1 does not yet write these — pre-ignored so v2 features don't pollute git). |
| `.squad/role-plan-*` | **Gitignore** | Per-role draft plans (reserved namespace; pre-ignored). |
| `.squad/features/*` | **Gitignore** | Feature-specific working state (reserved namespace; pre-ignored). |
| `.claude/agents/<role>.md` | **Commit** | Generated subagent definitions are part of the project's reproducible setup; committing them lets a teammate clone and run the same squad. |
| `.claude/worktrees/<role>/` | **Gitignore** | Git worktrees `spawn.sh` pre-creates for Multi-use teammates (per worktrees-doc tip); ephemeral, recreated on each spawn. |
| `.claude/workflows/squad-dispatch.js` | **Commit** | Generated dynamic-Workflow dispatch script (One-time mode, optional); committing it makes the squad's fan-out rerunnable by anyone who clones. |

The shipped `.gitignore` matches exactly this policy. Users who want their generated roles to stay private can move them to `~/.claude/agents/` instead (user scope) — Claude Code's subagent scanner finds both locations.

## Sequence diagram

Goal injection differs between the main session / teammates (SessionStart hook) and subagents (prompt-baking). The diagram shows both.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Onboard as squad-onboard
    participant Goal as squad-goal
    participant Role as squad-role
    participant Roster as squad-roster
    participant Spawn as squad-spawn
    participant Main as Main session
    participant SessionHook as SessionStart hook
    participant PromptHook as UserPromptSubmit hook
    participant PermHook as PermissionRequest hook
    participant Subagent as Subagent (one-time)
    participant Teammate as Agent Teams teammate (multi-use)

    Note over Main,SessionHook: At session start
    Main->>SessionHook: SessionStart fires (startup/resume)
    SessionHook->>Main: inject .squad/goal.md via additionalContext

    User->>Onboard: "I want to <X>"
    Onboard->>User: "Do you have a goal?"
    User->>Onboard: <user input>
    Onboard->>Onboard: reformulate as outcome, infer mode, confirm
    Onboard->>Goal: write .squad/goal.md
    Onboard->>Onboard: decompose into workstreams
    Onboard->>Role: generate role 1
    Role->>User: interactive questions per role
    Role->>Roster: register in .squad/roster.json
    Role->>Role: write .claude/agents/<name>.md + .squad/role-goal-<name>.md
    Onboard->>Role: generate role 2, role 3, …
    Onboard->>Spawn: dispatch the squad
    Spawn->>Goal: read .squad/goal.md
    Spawn->>Roster: read .squad/roster.json

    alt mode = one-time (subagents — SessionStart does NOT fire)
        Spawn->>Subagent: Task spawn with goal.md + role-goal.md baked into the Task prompt string (hard rule #4)
        Note right of Subagent: Subagent's context comes from the<br/>Task delegation message — there is<br/>no SessionStart hook to rely on.
    else mode = multi-use (Agent Teams teammates — SessionStart fires)
        Spawn->>Teammate: lead spawns each teammate (Agent Team) referencing .claude/agents/<role>.md by name, with a prompt containing goal.md + role-goal.md; spawn.sh has optionally pre-created a worktree per role
        Teammate->>SessionHook: SessionStart fires (teammate is a full Claude session)
        SessionHook->>Teammate: inject .squad/goal.md via additionalContext (redundant with prompt-baking — belt and suspenders)
    end

    Note over PromptHook,PermHook: Per-turn enforcement once the worker is running

    User->>PromptHook: prompt submitted (main session)
    PromptHook->>Main: append [squad goal in scope: …] tag via additionalContext
    Main->>PermHook: tool call requesting Bash/Edit/Write
    PermHook->>Roster: look up role by agent_type, check file_scope
    alt agent_type set and path in scope
        PermHook->>Main: decision: allow
    else agent_type absent or path out of scope
        PermHook->>User: defer — user prompted
    end

    Subagent-->>Main: deliverable summary
    Teammate-->>Main: deliverable summary
    Main->>User: synthesised result
```

## Agent Teams experimental status

[Agent Teams](https://code.claude.com/docs/en/agent-teams) is explicitly experimental and disabled by default. The plugin handles this in `squad-spawn`:

1. Read `$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from environment.
2. If `1` and mode is `multi-use`: proceed with Agent Teams path. File isolation (hard rule #7) is enforced by **disjoint per-role `file_scope`** (agent-teams doc: "break the work so each teammate owns a different set of files"). `skills/squad-spawn/scripts/spawn.sh` optionally pre-creates one git worktree per role as a working directory but launches no teammate; there is no `--worktree <role>` teammate-launch flag (that flag only starts standalone interactive sessions per the worktrees doc). The subagent-frontmatter `isolation: worktree` field is documented for subagents (One-time path), not teammates.
3. If unset or `0` and mode is `multi-use`:
   - Print a short explanation of what Agent Teams adds (shared task list, mailbox, direct teammate-to-teammate messaging).
   - Offer to add `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` to `~/.claude/settings.json` (asks consent first).
   - If user accepts: write the setting; instruct user to restart Claude Code; resume on next session.
   - If user declines: fall back to **sequential subagents** with a clear printed warning that mailbox / shared-task-list features are unavailable and the run will be slower than a true team.

The plugin never writes to `settings.json` without explicit user consent in the same turn.

## Dynamic Workflows — where they fit (and where they don't)

A [dynamic Workflow](https://code.claude.com/docs/en/workflows) is a JavaScript script the Claude Code runtime executes to orchestrate subagents at scale (deterministic fan-out, branching, loops; intermediate results held in script variables). cheeky-squad-os integrates it as an **optional dispatch backend for One-time mode** — surfaced by the `/cheeky-squad-os:squad-workflow` command and the canonical script `templates/squad-dispatch.workflow.js`.

### Where it fits: One-time only

| Mode | Workflow fit | Why |
| --- | --- | --- |
| **One-time** | ✅ Optional backend | One-time *is* fan-out N independent role-subagents then synthesize — exactly the workflow sweet spot. A workflow makes it deterministic, structured, and resumable. |
| **Multi-use** | ❌ Stays Agent Teams | Workflows forbid mid-run user input; Multi-use is interactive (shared task list, mailbox, address-a-teammate-by-name). The two are opposites. |
| **Evergreen** | ❌ Stays `/loop` + Routines | A workflow is not a scheduler. Scheduling stays with `/loop`, cloud Routines, or a desktop task. |

### What it solves (vs the default direct-`Agent` One-time path)

The default One-time path asks the orchestrator to remember, turn by turn, to batch all `Agent` calls, wait, then re-read every `file_scope` and synthesize. A workflow closes those gaps:

- **Deterministic fan-out** — one `agent()` per active role, every run, not model judgment.
- **Structured hand-off** — each role returns a schema'd `{role, summary, artifacts, status, follow_ups}` result, so synthesis is mechanical instead of free-text scraping.
- **Intermediate results off-context** — they live in a script variable; the main session's context holds only the final synthesis.
- **In-session resume** — a long N-role run survives interruption within the same session (it does **not** resume across a Claude Code restart).
- **Scale** — up to 16 concurrent / many agents per run, well past what hand-issued `Agent` calls comfortably manage.

A 2–3 role squad does **not** need this; the direct-`Agent` path stays the default. The workflow earns its overhead at 4+ roles or when adversarial cross-checking adds value.

### The constraints that shaped the integration (all verified against the docs)

1. **A skill cannot launch a workflow.** Triggers are: the literal keyword `workflow` in a user prompt, `/effort ultracode`, a bundled command, or a saved `/<name>` command — and each run needs user approval. So `squad-spawn` cannot silently escalate into a workflow; it *points the user* at `/cheeky-squad-os:squad-workflow`, which is the user-triggered entry.
2. **Workflow subagents run in `acceptEdits`.** Their file edits are auto-approved, which **bypasses the `PermissionRequest` file-scope hook** — the plugin's core write-discipline control. Compensating design: the dispatch workflow fans out **read/analyze** roles that write only inside their own `file_scope` (stated as a hard boundary in every baked agent prompt). Roles that mutate shared code stay on the hook-gated `squad-spawn` path, or run as their own write-stage workflow with a sign-off gate between stages.
3. **No filesystem access in the script.** A workflow script can't read `.squad/`. So `/cheeky-squad-os:squad-workflow` bakes the goal text, each role's role-goal, `file_scope`, and task into the workflow's `args` (this *is* hard rule #4); the spawned agents, being real subagents, additionally re-read the files.
4. **Availability.** Research preview, recent Claude Code, paid plans, org-disablable. The command detects unavailability and **falls back** to the direct-`Agent` One-time path.

### How a dispatch runs

`/cheeky-squad-os:squad-workflow` preflights (goal + roster + mode=one-time), gates on availability and squad size, briefs the user on the `acceptEdits` posture, assembles `args` from the live roster, then authors/runs a script shaped like `templates/squad-dispatch.workflow.js`: one `agent()` per active role with `agentType` set to the role name (so `.claude/agents/<name>.md` loads) and a structured-output schema, then a synthesis phase. With `--save`, the concrete script is written to `.claude/workflows/squad-dispatch.js` (committed, rerunnable — regenerate when the roster changes).

## Cross-tool portability

Per the agentskills.io spec, the SKILL.md bodies contain no Claude-Code-specific behavior. Claude-Code-specific concerns:

- **Agent Teams enablement** — the env check lives in `skills/squad-spawn/scripts/spawn.sh`, not in the skill body.
- **Worktree pre-creation** — `skills/squad-spawn/scripts/spawn.sh` runs `git worktree add` to pre-create one optional working directory per role. It launches no teammate, and there is no `--worktree` teammate-launch flag.
- **`/loop` and Routines** — referenced in `squad-spawn` body, but the skill degrades gracefully on non-Claude-Code tools (it would describe scheduling abstractly).
- **Hook installation** — done by `plugin.json`, not the skills.

A user running these skills under a different agent runner gets the discipline (one-question goal flow, outcome reformulation, mode inference, role generation, prompt-baking) without the Claude-Code-specific orchestration.

## Failure modes

| Failure | Behavior |
| --- | --- |
| `squad-spawn` invoked with no `.squad/goal.md` | Refuse, point user at `/cheeky-squad-os:squad-onboard` |
| `squad-spawn` invoked with empty `.squad/roster.json` | Refuse, point user at `squad-role` |
| Agent Teams env unset in multi-use mode | Offer to enable; fall back to sequential subagents on decline |
| `PermissionRequest` hook errors | Exit 0 with no decision — user prompted, never silently allowed |
| `SessionStart` hook errors | Exit 0 — never block session start |
| `UserPromptSubmit` hook errors | Exit 0 — never block user turns (v1 is observational) |
| `squad-role` invoked with no goal | Refuse, point user at `squad-onboard` |
| Role name collision in `.claude/agents/` | Refuse, prompt user to choose a different name |

## What v1 deliberately does not do

- **Drift blocking.** `UserPromptSubmit` observes; it does not refuse. Drift policy is v2.
- **Cross-session role memory.** `memory:` frontmatter on generated subagents is supported by Claude Code (per sub-agents doc) but not auto-set by `squad-role` in v1. Future flag.
- **Squad-of-squads composition.** Subagents can't spawn subagents (per docs). v1 does not model nested squads.
- **Automatic mode escalation.** If a one-time turns into a multi-use, the user re-runs `squad-onboard`. No silent migration.
- **Roster sync to remote.** All state is local under `.squad/`. Future: optional sync.

## Version targets

These are the features the plugin leans on and the surfaces that gate them. The exact minimum version numbers below are **approximate** — treat them as "a recent Claude Code" and verify against your installed `claude --version` rather than as hard guarantees:

- `/goal` (Phase 7 smoke test uses it)
- `/loop` (Evergreen mode option) — in-session recurring task
- **Agent Teams** (Multi-use mode) — experimental, env-gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- **Dynamic Workflows** (optional One-time dispatch) — **research preview, paid plans, ~v2.1.154+**, can be org-disabled (`disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS`). See ["Dynamic Workflows"](#dynamic-workflows--where-they-fit-and-where-they-dont).
- Plugin manifest follows the schema documented at [plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

The plugin gracefully degrades on surfaces it can't reach: missing Agent Teams falls back to subagents; missing/disabled Workflows falls back to the direct-`Agent` One-time path.

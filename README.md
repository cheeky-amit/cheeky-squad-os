<div align="center">

# 🪖 cheeky-squad-os

### Ship the discipline, not the team.

*Turn any Claude Code goal — engineering, ops, business infrastructure, knowledge work — into a **bespoke squad of roles generated from the goal itself**. Zero opinionated roles shipped.*

<br/>

[![CI](https://github.com/cheeky-amit/cheeky-squad-os/actions/workflows/ci.yml/badge.svg)](https://github.com/cheeky-amit/cheeky-squad-os/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](.claude-plugin/plugin.json)
[![Claude Code plugin](https://img.shields.io/badge/Claude_Code-plugin-8A2BE2.svg)](https://code.claude.com/docs/en/plugins)
[![Built with](https://img.shields.io/badge/built_with-Markdown_%2B_Bash-1f425f.svg)](CONTRIBUTING.md)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

<br/>

**[Why](#why-this-matters-across-domains)** ·
**[How it works](#how-it-works)** ·
**[Hooks](#the-three-hooks)** ·
**[Modes](#the-three-modes)** ·
**[Workflows](#dynamic-workflows-optional-one-time-mode)** ·
**[Install](#installation)** ·
**[Components](#the-seven-skills--three-hooks)** ·
**[Roadmap](docs/ROADMAP.md)** ·
**[Contributing](CONTRIBUTING.md)**

</div>

---

> All Claude Code work — engineering, operational, agentic business infrastructure, knowledge work — goes better when you treat your AI session like a team with roles, responsibilities, communication, and supervision. **cheeky-squad-os ships the discipline, not the team.**

Your goal generates the team. Every squad is bespoke to the goal that spawned it. The plugin contains zero opinionated roles — no `frontend-dev`, no `backend-dev`, no defaults. The role generator builds what each goal needs, when the goal needs it, in the shape the goal demands.

---

## Why this matters across domains

The same primitives serve four distinct kinds of work:

| Domain | What it covers | Example goal |
| --- | --- | --- |
| 🛠️ **Engineering** | features, refactors, migrations | *"Ship a new homepage that converts at >5% by end of sprint."* |
| 🔁 **Operational agents** | weekly reports, scheduled audits, alert handling | *"Every Monday produce a 1-page competitor movement summary."* |
| 📊 **Business infrastructure** | lifecycle audits, recurring research, content | *"Deliver a ranked Klaviyo lifecycle fix list with revenue impact in a week."* |
| 🧠 **Knowledge work** | audits, analyses, decision memos | *"Draft a build-vs-buy memo for the analytics stack by Friday."* |

The role generator is domain-neutral. A Klaviyo audit gets `klaviyo-data-puller` + `compliance-checker` + `report-writer`. A homepage redesign gets `brand-voice-editor` + `conversion-ux-designer` + `frontend-builder` + `qa-runner`. Every squad is named for what it does — not for what default the framework happens to ship.

---

## How it works

One skill chain — onboard → role → env → spawn → verify, with the goal and roster as shared state — carries you from a vague intent to a dispatched, supervised, **verified** team. Three hooks keep every turn anchored to the goal.

```mermaid
flowchart LR
  U(["🧑 You: a goal"]) --> ON

  subgraph S1["1 · squad-onboard"]
    ON["Reformulate as a<br/>measurable outcome"] --> MODE{"Infer mode"}
  end
  ON --> GOAL[(".squad/goal.md<br/>north-star")]

  MODE --> ROLE

  subgraph S2["2 · squad-role"]
    ROLE["Interactive role<br/>generator"] --> AG[".claude/agents/&lt;role&gt;.md"]
    ROLE --> ROST[(".squad/roster.json")]
  end

  AG --> SPAWN
  ROST --> SPAWN

  subgraph S3["3 · squad-spawn"]
    SPAWN{"Branch on mode"} --> ONE["One-time → subagents"]
    SPAWN --> MUL["Multi-use → Agent Teams"]
    SPAWN --> EVR["Evergreen → scheduling"]
  end

  ONE --> OUT(["📦 Deliverables"])
  MUL --> OUT
  EVR --> OUT

  subgraph S4["4 · squad-verify"]
    VER["Check the<br/>Definition of done"] --> VMD[(".squad/verification.md<br/>met · partial · unmet")]
  end

  OUT --> VER

  GOAL -. binding .-> SPAWN
  GOAL -. definition of done .-> VER
```

1. **Set a north-star goal** with `/cheeky-squad-os:squad-onboard`. It asks *"Do you have a goal?"*, reformulates your answer as a measurable, time-bounded outcome, infers the mode (one-time / multi-use / evergreen), and decomposes the work into parallel workstreams. The confirmed goal is saved to `.squad/goal.md`.
2. **Generate the roles your goal needs** with `/cheeky-squad-os:squad-role`. For each workstream, an interactive flow asks what the role does, what files it owns, what tools it needs, what model fits. Each role is written to `.claude/agents/<role-name>.md` and registered in `.squad/roster.json`.
3. **Spawn the squad** with `/cheeky-squad-os:squad-spawn`. It branches on the squad's mode (see below).
4. **Verify the work** with `/cheeky-squad-os:squad-verify`. When the squad reports done, it checks every Definition-of-done signal against the deliverables (PASS / FAIL / NEEDS-HUMAN — never guessed), computes a met / partial / unmet verdict, and writes `.squad/verification.md`. Synthesis summarizes; verification decides.
5. **The hooks enforce the contract every turn** (see below).

---

## The three hooks

Registered inline in `plugin.json`; they fire on the next session start.

```mermaid
sequenceDiagram
  autonumber
  participant CC as Claude Code
  participant SS as SessionStart
  participant UP as UserPromptSubmit
  participant PR as PermissionRequest
  participant FS as .squad / files

  CC->>SS: session starts
  SS->>FS: read .squad/goal.md
  FS-->>SS: goal text
  SS-->>CC: inject goal as additionalContext
  Note over CC: goal is now in scope

  CC->>UP: user submits a prompt
  UP-->>CC: append "[squad goal in scope: ...]" (observational)

  CC->>PR: subagent wants Bash/Edit/Write
  alt Edit/Write in role file_scope · or scaffolding Bash inside role sandbox
    PR-->>CC: auto-approve
  else out of scope / any other Bash / unknown role / error
    PR-->>CC: defer to user (fail-open, never silently denies)
  end
```

- **`SessionStart`** — reads `.squad/goal.md` and injects it as additional context on every session start. If no goal is set, prints a one-line nudge to run `squad-onboard`.
- **`UserPromptSubmit`** — appends `[squad goal in scope: <first 80 chars>]` to every turn so drift is visible. Observational only in v1 — does not block.
- **`PermissionRequest`** — auto-approves two narrow surfaces for registered subagents: (a) Edit/Write inside the role's registered `file_scope`, and (b) in-sandbox scaffolding Bash — verbs `mkdir`/`touch`/`cp`/`ln` only, no shell metacharacters, every path operand inside the role's `environment.workspace`. Everything else — out of scope, any other Bash, any other tool, main session, unknown role — defers to the user. Fail-open on errors — never silently denies.

### How the permission hook decides

```mermaid
flowchart TD
  A["PermissionRequest fires"] --> B{"agent_type present?"}
  B -- "no / main session" --> D["↩️ defer to user"]
  B -- yes --> C{"tool?"}
  C -- "Edit / Write" --> E{"file_path inside<br/>role file_scope?"}
  E -- "no / traversal / outside repo" --> D
  E -- yes --> F["✅ allow this single call"]
  C -- Bash --> G{"role has<br/>environment.workspace?"}
  G -- no --> D
  G -- yes --> H{"verb in mkdir·touch·cp·ln,<br/>no shell metacharacters?"}
  H -- no --> D
  H -- yes --> I{"every path operand<br/>inside the workspace?"}
  I -- "no / traversal" --> D
  I -- yes --> F
  C -- "other · e.g. MCP" --> D
```

Bash defers unless it is pure scaffolding fully contained in the role's declared sandbox. Auto-approval only ever widens to a subagent writing inside the files its role owns — or scaffolding inside its own sandbox.

---

## The three modes

`squad-spawn` branches on the mode that `squad-onboard` inferred.

```mermaid
flowchart LR
  M{"Mode?"} -->|one-time| O["Agent tool x N roles<br/>goal baked into prompt"]
  M -->|multi-use| T{"AGENT_TEAMS = 1?"}
  M -->|evergreen| E["Pick: /loop · Routine · desktop task"]

  T -->|yes| TT["Lead spawns teammates by name<br/>ref .claude/agents/&lt;role&gt;.md"]
  T -->|no| O2["Fall back to subagents"]
  TT -. optional .-> WT["spawn.sh pre-creates git worktrees<br/>(git worktree add only —<br/>does NOT launch teammates)"]
```

- **One-time** — bounded deliverable, single push. Uses subagents. The full text of `.squad/goal.md` and the role's role-goal is baked into every spawn prompt — the only reliable parent→worker channel (the SessionStart hook does **not** fire for subagents).
  *Example: "Deliver a ranked list of Klaviyo lifecycle fixes within one week." See `examples/klaviyo-audit.md`.*
- **Multi-use** — ongoing build over multiple workstreams. Uses Agent Teams (experimental, env-gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; falls back to sequential subagents when unset). Teammate file isolation is enforced by giving each role a **disjoint `file_scope`**. The team lead spawns each teammate by referencing its `.claude/agents/<role>.md` **by name**. As an optional convenience, `skills/squad-spawn/scripts/spawn.sh` can pre-create one git worktree per role — it only runs `git worktree add`; it does **not** launch teammates, and there is **no `--worktree` teammate-launch flag**.
  *Example: "Ship a new homepage that converts at >5%, deployed by end of sprint." See `examples/landing-page-redesign.md`.*
- **Evergreen** — recurring, scheduled. The plugin sets up the goal and roles, then surfaces three scheduling options (`/loop`, cloud Routine, desktop scheduled task) for you to pick.
  *Example: "Every Monday produce a 1-page competitor summary." See `examples/weekly-competitive-intel.md`.*

---

## Dynamic Workflows (optional, One-time mode)

For larger One-time squads, dispatch can run as a Claude Code **dynamic Workflow** — run `/cheeky-squad-os:squad-workflow`. You get deterministic fan-out, schema'd hand-offs, intermediate results held off the main context, and in-session resume.

```mermaid
flowchart TD
  CMD["/cheeky-squad-os:squad-workflow"] --> BAKE["Bake goal + roster into args<br/>(workflow has no filesystem access)"]
  BAKE --> FAN{{"Deterministic fan-out"}}
  FAN --> R1["agent · role A"]
  FAN --> R2["agent · role B"]
  FAN --> R3["agent · role C"]
  R1 --> SY["Synthesize structured digest"]
  R2 --> SY
  R3 --> SY
  SY --> REP(["📋 One report"])
```

> ⚠️ **Caveat:** workflow subagents run with file edits auto-approved, which bypasses the file-scope hook. So this path fans out **read/analyze** roles with self-policed scoped writes, while code-mutating roles stay on the hook-gated `squad-spawn` path. It's opt-in, approved per run, and falls back to standard dispatch when Workflows aren't available. Full design: [ARCHITECTURE.md](ARCHITECTURE.md#dynamic-workflows--where-they-fit-and-where-they-dont). Runtime contract details (the Workflow DSL behind `templates/squad-dispatch.workflow.js`): [docs/workflows-runtime-reference.md](docs/workflows-runtime-reference.md).

---

## Installation

```text
/plugin marketplace add cheeky-amit/cheeky-squad-os
/plugin install cheeky-squad-os@cheeky-squad-os
```

*(Replace `cheeky-amit` with your own org if you've forked the repo.)*

After install, the `SessionStart` hook fires on the **next** session start — open a fresh session, or run `/reload-plugins` if you installed mid-session, to pick the hooks up. Then set your first goal:

```text
/cheeky-squad-os:squad-onboard
```

### Setup steps

1. **Check prerequisites** — Claude Code with plugin support, plus `jq` and `git` on your `PATH`:
   ```bash
   claude --version
   which jq      # brew install jq   (macOS)  /  apt-get install jq  (Linux)
   git --version
   ```
   The hooks and `spawn.sh` degrade gracefully without `jq`, but full goal injection and the Multi-use worktree helper require it.
2. **Add the marketplace & install** (commands above).
3. **Reload hooks** — start a fresh session or run `/reload-plugins`.
4. **Verify** — run `/hooks` and confirm all three hooks are wired; ask *"What's our squad goal?"* and you should get the "no goal set" nudge from the `SessionStart` hook.
5. **Onboard** — run `/cheeky-squad-os:squad-onboard` and answer the goal question.
6. **Generate roles** — run `/cheeky-squad-os:squad-role` for each proposed workstream.
7. **Provision environments** *(optional)* — run `/cheeky-squad-os:squad-env` to build each role's sandbox (workspace, env, seeded reference material, tools) before dispatch. `squad-spawn` also triggers this automatically for roles that declare an `environment`.
8. **Spawn** — run `/cheeky-squad-os:squad-spawn` to dispatch the squad.
9. **Verify** — run `/cheeky-squad-os:squad-verify` when the squad reports done; it checks the Definition of done and writes `.squad/verification.md`.

See [`tests/smoke-test.md`](tests/smoke-test.md) for a copy-pasteable end-to-end walkthrough that exercises every skill and hook.

---

## The seven skills & three hooks

| Component | Kind | What it does |
| --- | --- | --- |
| `squad-onboard` | skill | Reformulates a goal as an outcome, infers mode, proposes a bespoke squad. |
| `squad-goal` | skill | Manages `.squad/goal.md` as the binding north-star. |
| `squad-role` | skill | Interactive role generator → `.claude/agents/<role>.md` + roster. |
| `squad-env` | skill | Provisions each role's sandbox (workspace, env, tools) from the goal; proposes what it can't contain. |
| `squad-spawn` | skill | Dispatches the squad, branching on mode. |
| `squad-roster` | skill | Manages `roster.json` + auto-generated `roster.md`. |
| `squad-verify` | skill | Verifies deliverables against the goal's Definition of done; writes `.squad/verification.md` with a met/partial/unmet verdict. |
| `SessionStart` | hook | Injects the goal into every session. |
| `UserPromptSubmit` | hook | Tags each turn with the goal (observational). |
| `PermissionRequest` | hook | Auto-approves in-scope Edit/Write + in-sandbox scaffolding; defers everything else. |

---

## What this plugin does NOT ship

- ✕ **Zero role files.** No `frontend-dev`, no `backend-dev`, no `qa-engineer`. The generator builds what your goal needs.
- ✕ **No fixed team structure.** A 3-role audit and a 6-role build are both valid squads — size comes from decomposition.
- ✕ **No assumption you're an engineer.** An ops loop and a marketing audit use the same primitives as a feature build.

This is intentional. Defaults bias every goal toward the shape the defaults assume. The plugin's design forces you to think about what your goal actually needs — and then build exactly that.

---

## Plugin contents at a glance

```text
cheeky-squad-os/
├── .claude-plugin/
│   ├── plugin.json                  # metadata + inline hook registration
│   └── marketplace.json
├── skills/
│   ├── squad-onboard/SKILL.md
│   ├── squad-goal/SKILL.md
│   ├── squad-role/SKILL.md
│   ├── squad-env/
│   │   ├── SKILL.md
│   │   └── scripts/provision.sh     # per-role sandbox provisioner
│   ├── squad-spawn/
│   │   ├── SKILL.md
│   │   └── scripts/spawn.sh         # multi-use worktree pre-creation helper
│   ├── squad-verify/
│   │   ├── SKILL.md
│   │   └── scripts/verify.sh        # definition-of-done evidence scaffold
│   └── squad-roster/SKILL.md
├── commands/
│   └── squad-workflow.md            # optional Workflow dispatch (One-time)
├── hooks/
│   ├── session-start.sh
│   ├── user-prompt-submit.sh
│   └── permission-request.sh
├── templates/
│   ├── goal.md
│   ├── role-goal.md
│   ├── role-definition.md
│   ├── roster.json
│   ├── verification.md              # squad-verify report skeleton
│   └── squad-dispatch.workflow.js   # canonical fan-out + synthesize script
├── docs/
│   ├── ROADMAP.md                   # measurable path to the north star, ranked gaps
│   └── workflows-runtime-reference.md  # verified Workflow DSL runtime reference
├── examples/
│   ├── klaviyo-audit.md
│   ├── landing-page-redesign.md
│   └── weekly-competitive-intel.md
├── tests/
│   ├── smoke-test.md                # manual end-to-end walkthrough
│   ├── permission-request.bats      # automated: hook allow/defer matrix
│   ├── spawn.bats                   # automated: spawn.sh preflight + worktrees
│   ├── provision.bats               # automated: provision.sh sandbox build
│   └── verify.bats                  # automated: verify.sh evidence scaffold
├── .github/
│   └── workflows/ci.yml             # shellcheck + bats on push/PR
├── ARCHITECTURE.md
├── LOGIC.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── LICENSE (MIT)
└── README.md
```

---

## License

[MIT](LICENSE) © cheeky-amit.

<div align="center">
<br/>

**Ship the discipline, not the team.**

<sub>Built as a Claude Code plugin · skills + hooks, no fixed roster · <a href="#-cheeky-squad-os">back to top ↑</a></sub>

</div>

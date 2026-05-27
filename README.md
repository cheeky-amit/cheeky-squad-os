# cheeky-squad-os

> All Claude Code work — engineering, operational, agentic business infrastructure, knowledge work — goes better when you treat your AI session like a team with roles, responsibilities, communication, and supervision. **cheeky-squad-os ships the discipline, not the team.**

Your goal generates the team. Every squad is bespoke to the goal that spawned it. The plugin contains zero opinionated roles — no `frontend-dev`, no `backend-dev`, no defaults. The role generator builds what each goal needs, when the goal needs it, in the shape the goal demands.

---

## Why this matters across domains

The same primitives serve four distinct kinds of work:

- **Engineering work** — features, refactors, migrations. *"Ship a new homepage that converts at >5% by end of sprint."*
- **Operational agents** — weekly reports, scheduled audits, alert handling. *"Every Monday produce a 1-page competitor movement summary."*
- **Agentic business infrastructure** — lifecycle marketing audits, recurring research, content production. *"Deliver a ranked Klaviyo lifecycle fix list with revenue impact estimates within one week."*
- **Knowledge work** — audits, analyses, decision memos. *"Draft a build-vs-buy memo for the analytics stack with cost projections by Friday."*

The role generator is domain-neutral. A Klaviyo audit gets `klaviyo-data-puller` + `compliance-checker` + `report-writer`. A homepage redesign gets `brand-voice-editor` + `conversion-ux-designer` + `frontend-builder` + `qa-runner`. Every squad is named for what it does — not for what default the framework happens to ship.

---

## The workflow

1. **Set a north-star goal** with `/cheeky-squad-os:squad-onboard`. The skill asks one question — *"Do you have a goal?"* — reformulates your answer as a measurable, time-bounded outcome, infers the squad's mode (one-time / multi-use / evergreen), and decomposes the work into parallel workstreams. The confirmed goal is saved to `.squad/goal.md` — the binding north-star.

2. **Generate the roles your goal needs** with `/cheeky-squad-os:squad-role`. For each workstream, an interactive flow asks what the role does, what files it owns, what tools it needs, what model is appropriate. Each role is written to `.claude/agents/<role-name>.md` and registered in `.squad/roster.json`. Roles could be a researcher and a writer, a security-auditor and a compliance-checker, a scraper and an analyst — anything the goal demands.

3. **Spawn the squad** with `/cheeky-squad-os:squad-spawn`. The skill branches on the squad's mode: One-time dispatches subagents; Multi-use uses Agent Teams with per-teammate git worktrees (file isolation); Evergreen surfaces three scheduling options (`/loop`, cloud Routine, desktop scheduled task) for the user to pick.

4. **The hooks enforce the contract every turn.** SessionStart injects the squad goal into every new session's context. UserPromptSubmit appends a one-line "goal in scope" tag on every prompt. PermissionRequest auto-approves Bash/Edit/Write inside the active role's file scope and defers to the user otherwise.

---

## Installation

```
/plugin marketplace add <github-org>/cheeky-squad-os
/plugin install cheeky-squad-os@cheeky-squad-os
```

Replace `<github-org>` with the org hosting the repo. After install, the SessionStart hook starts firing immediately. Run `/cheeky-squad-os:squad-onboard` to set your first goal.

---

## The five skills

- **`squad-onboard`** — entry point. Asks "do you have a goal?", reformulates as an outcome, infers mode, decomposes work, proposes a bespoke squad, hands off to `squad-role`.
- **`squad-goal`** — manages `.squad/goal.md` as the binding north-star outcome.
- **`squad-role`** — interactive role generator. Writes `.claude/agents/<role-name>.md` from the user's answers; registers the role in the roster.
- **`squad-spawn`** — dispatches the squad. Branches on mode (One-time → subagents, Multi-use → Agent Teams + worktrees, Evergreen → scheduling options).
- **`squad-roster`** — manages `.squad/roster.json` (source of truth) and `.squad/roster.md` (auto-generated human view).

---

## The three hooks

- **`SessionStart`** — reads `.squad/goal.md` and injects it as additional context on every session start. If no goal is set, prints a one-line nudge to run `squad-onboard`.
- **`UserPromptSubmit`** — appends `[squad goal in scope: <first 80 chars>]` to every user turn so drift is visible. Observational only in v1 — does not block.
- **`PermissionRequest`** — when a subagent or teammate calls Edit/Write inside its registered file scope, auto-approves. Outside scope or unknown role, defers to the user. Fail-open on errors — never silently denies.

---

## The three modes

**One-time** — bounded deliverable, single push. Uses subagents.
Example goal: *"Deliver a ranked list of Klaviyo lifecycle fixes with revenue impact estimates within one week."* See `examples/klaviyo-audit.md` for a full walkthrough.

**Multi-use** — ongoing build, multiple workstreams over time. Uses Agent Teams (experimental in Claude Code, env-gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) with `--worktree` per teammate for file isolation.
Example goal: *"Ship a new homepage that converts at >5% with the existing brand voice, deployed by end of sprint."* See `examples/landing-page-redesign.md` for a full walkthrough.

**Evergreen** — recurring, scheduled. The plugin sets up the goal and roles, then surfaces three scheduling options (`/loop`, cloud Routine, desktop scheduled task) for the user to pick.
Example goal: *"Every Monday produce a 1-page summary of competitor pricing, product, and positioning shifts from the prior week."* See `examples/weekly-competitive-intel.md` for a full walkthrough.

---

## What this plugin does NOT ship

- **Zero role files.** No `frontend-dev`, no `backend-dev`, no `qa-engineer`. The role generator builds what your goal needs.
- **No fixed team structure.** Squad size and composition are decided by goal decomposition. A 3-role audit and a 6-role build are both valid squads.
- **No assumption that this is for engineers.** The framework is domain-neutral. An ops loop and a marketing audit use the same primitives as a feature build.

This is intentional. Defaults bias every goal toward the shape the defaults assume. A Klaviyo audit doesn't need a `backend-dev`. A weekly intel loop doesn't need a `qa-engineer`. The plugin's design forces you to think about what your goal actually needs — and then build exactly that.

---

## Plugin contents at a glance

```
cheeky-squad-os/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── squad-onboard/SKILL.md
│   ├── squad-goal/SKILL.md
│   ├── squad-role/SKILL.md
│   ├── squad-spawn/
│   │   ├── SKILL.md
│   │   └── scripts/spawn.sh
│   └── squad-roster/SKILL.md
├── hooks/
│   ├── session-start.sh
│   ├── user-prompt-submit.sh
│   └── permission-request.sh
├── templates/
│   ├── goal.md
│   ├── role-goal.md
│   ├── role-definition.md
│   └── roster.json
├── examples/
│   ├── klaviyo-audit.md
│   ├── landing-page-redesign.md
│   └── weekly-competitive-intel.md
├── tests/
│   └── smoke-test.md
├── ARCHITECTURE.md
├── CONTRIBUTING.md
├── LICENSE (MIT)
└── README.md
```

---

## License

MIT. Author: amit-cheeky.

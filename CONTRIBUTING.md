# Contributing to cheeky-squad-os

This is a small plugin with a clear shape. Contributions land in one of five places. Pick the one your change targets and follow the conventions for that surface.

## Repo layout (the actual files)

```
.claude-plugin/        plugin manifest + self-marketplace
hooks/                 three bash scripts (SessionStart, UserPromptSubmit, PermissionRequest)
skills/<name>/SKILL.md five SKILL.md files (squad-onboard, squad-goal, squad-role, squad-spawn, squad-roster)
skills/squad-spawn/scripts/spawn.sh  multi-use mode worktree pre-creation helper
commands/              squad-workflow.md (optional One-time Workflow dispatch)
templates/             goal.md, role-goal.md, role-definition.md, roster.json, squad-dispatch.workflow.js
examples/              three walkthrough docs (one per mode)
tests/                 smoke-test.md (manual) + permission-request.bats / spawn.bats (automated)
.github/workflows/     ci.yml — shellcheck + bats on push/PR
ARCHITECTURE.md        full design doc
```

Almost everything is markdown and bash. The two exceptions: `templates/squad-dispatch.workflow.js` is the canonical dynamic-Workflow dispatch script (JavaScript, run by the Claude Code Workflow runtime), and the shell scripts are covered by a `bats` suite + `shellcheck` in CI. No Python, no build step.

## What you can contribute

### 1. A new skill

Add a directory under `skills/<your-skill-name>/` containing a single `SKILL.md`. Follow the YAML frontmatter conventions used by the existing five skills:

```yaml
---
name: <kebab-case>
description: <when Claude should auto-invoke — include trigger phrases across domains>
version: 0.1.0
author: <your handle>
license: MIT
compatible-with: [claude-code, agentskills-1.0]
---
```

Constraints:
- Body under 200 lines. Bundle longer content in a `references/` subfolder if needed.
- `description` field is what determines auto-invocation. Include phrases users would actually say, across the four domains (engineering, ops, business infra, knowledge work).
- Skill body must not contain Claude-Code-specific orchestration logic. That lives in scripts under `scripts/` (see `squad-spawn` for the pattern). This keeps skills cross-tool portable per agentskills.io.
- If your skill spawns workers, you must respect hard rule #4: bake `.squad/goal.md` and the relevant role goal text into every spawn prompt. The SessionStart hook does not fire for subagents.

Skills that touch `.squad/` state should hand off to the existing CRUD skill rather than rewriting it:
- Read/write `.squad/goal.md` → use `squad-goal`
- Read/write `.squad/roster.json` → use `squad-roster`
- Generate a role → use `squad-role`

### 2. Modifying a hook

The three hooks live at `hooks/session-start.sh`, `hooks/user-prompt-submit.sh`, `hooks/permission-request.sh`. Constraints:

- **Bash.** POSIX-compatible where possible, but bash extensions are allowed (the shebang is `#!/usr/bin/env bash`).
- **Always exit 0.** Any error path must fail open. Hooks must not block agent execution.
- **No `set -e`.** Use `set -u` if you want strict variable checking, but never let a sub-shell failure propagate as an exit code.
- **Defer rather than deny.** PermissionRequest must never silently deny. Omit the decision and let normal permission flow handle out-of-scope calls — the user decides.
- **jq is preferred but not required.** If jq is missing, fail open (defer to user for security decisions; emit a static fallback notice for context injection).

Hook changes need to be smoke-tested against the input JSON shapes documented at <https://code.claude.com/docs/en/hooks>. The existing hooks have a working test pattern in `tests/smoke-test.md` — extend or mimic that.

### 3. The role-definition template

`templates/role-definition.md` is the schema every generated role derives from. If you want every future generated role to behave differently, change the template — don't change individual role files (those are user-generated and user-owned).

Constraints:
- Keep the YAML frontmatter compatible with Claude Code's subagent fields (see <https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields>). The frontmatter is `name`, `description`, `tools`, `model`, optionally `isolation`.
- All `{{placeholder}}` values must be substitutable by `squad-role` from its interactive Q&A.
- Document every new placeholder in the comment block at the top of the file.
- The body becomes a subagent system prompt AND, in Multi-use mode, gets appended to an Agent Teams teammate's system prompt. Per Claude Code's agent-teams doc, `skills` and `mcpServers` frontmatter fields do not propagate when used as a teammate; `tools` and `model` do. Reflect this constraint in any frontmatter additions.

### 4. Proposing a new mode

cheeky-squad-os ships three modes — One-time, Multi-use, Evergreen — because those are the three cadences observed across engineering, ops, business infrastructure, and knowledge work. A new mode needs to justify itself:

- What cadence/persistence does it cover that the existing three don't?
- What Claude Code primitive backs it?
- How does it interact with the SessionStart hook (i.e., does the goal load via hook injection or via prompt-baking)?
- How does `squad-spawn` branch on it?

Open an issue first with a proposed mode definition. A proposed mode should arrive with at least one concrete example goal that needs it. Don't add modes that subdivide the existing three.

### 5. Examples and docs

The three example walkthroughs in `examples/` should each cover one mode AND one domain — and the domains must stay diverse. If you contribute another example, make sure it adds a domain that isn't already represented (e.g., a knowledge-work audit, a content-production pipeline, a CI babysitter).

When you add a new example, use role names that don't collide with any of the existing examples. The point of the framework is that role names are bespoke per goal — example files should reinforce that, not erode it.

## Style

- Markdown is GitHub-flavoured CommonMark.
- Bash scripts get a header comment block explaining what the script does, what it expects on stdin, what it emits on stdout, and its fail-mode contract.
- Skill bodies address the model in second person ("you do X"), since they become system-prompt context.
- Role-template body addresses the role in second person too. The role IS the reader.
- No emoji in plugin-shipped files.

## Local testing

Two layers:

**Automated** — a `bats` suite over the shell scripts, gated in CI (`.github/workflows/ci.yml`) alongside `shellcheck`:

```
shellcheck hooks/*.sh skills/**/scripts/*.sh
bats tests/permission-request.bats tests/spawn.bats
```

`permission-request.bats` covers the hook's allow/defer matrix (in-scope allow, out-of-scope/Bash/main-session/unknown-role defer, single-segment glob semantics, `..` traversal defer, missing-jq fail-open). `spawn.bats` covers `spawn.sh` preflight refusals and idempotent worktree creation. Install the tools with `brew install bats-core shellcheck` (macOS) or `apt-get install bats shellcheck` (Linux). These run automatically on every push/PR.

**Manual end-to-end** — the interactive surface (skills, SessionStart injection, real subagent dispatch) isn't covered by bats. Run the walkthrough at `tests/smoke-test.md` before opening a PR:

```
/plugin marketplace add ./
/plugin install cheeky-squad-os@cheeky-squad-os
```

Then follow the steps in `tests/smoke-test.md`. It exercises every skill and every hook with a real (but tiny) goal. If your change breaks the smoke test, the PR isn't ready.

For hook changes, you can also pipe synthetic JSON into the hook script directly and inspect the output — that's exactly what `tests/permission-request.bats` automates, and the manual pattern is shown in `tests/smoke-test.md`.

## Issues

When filing a bug, include:
- Claude Code version (`claude --version`)
- Plugin version (`/plugin list`)
- The contents of `.squad/goal.md` and `.squad/roster.json` at the time of the bug (redact business-sensitive content)
- What you ran and what happened vs what you expected

When proposing a feature, lead with the goal that needs it. A feature without a goal it serves isn't ready to ship in this plugin — the plugin's whole shape is "goals first".

## License

By contributing, you agree your contribution is licensed under the MIT License.

---
name: squad-env
description: Use when the user wants each role to have its working environment set up before the squad runs — phrases like "set up the workspaces", "provision the environments", "build each role's sandbox", "prepare the squad to run", "what does each role need", or any "get ready to dispatch" signal after roles are generated. Derives a per-role environment (sandbox dir, env file, reference material, tool readiness) from the goal + role goal + domain, then materializes it via scripts/provision.sh. Runs everything it can CONTAIN inside each role's sandbox autonomously, and PROPOSES the few things it cannot contain (system packages, MCP servers, network fetches, global flags) for the user to approve. Also invoked by squad-spawn before dispatch.
version: 0.1.0
author: cheeky-squad-os
license: MIT
allowed-tools: [Read, Write, Edit, Bash]
compatible-with: [claude-code, agentskills-1.0]
---

# squad-env

You provision role environments. Each active role gets a **sandbox** — a filesystem-and-PATH boundary it works inside freely. You materialize what can be contained, and you surface what cannot.

The sandbox is **not** a kernel jail. It is:
- a per-role workspace dir (`.squad/workspaces/<role>/`) with scaffolded subdirs,
- a role-local `bin/` and a `env` file that the role *sources* (never exported globally),
- locally copied/linked reference material,
- tools verified present; local tools installed *into* the sandbox.

The one safety rule, end to end: **contain what you can, propose what you can't.** Nothing that mutates the user's machine outside a sandbox is ever run without the user seeing and approving it.

## Preflight — refuse if not ready

1. Read `.squad/goal.md`. If absent: refuse with *"No squad goal set. Run `/cheeky-squad-os:squad-onboard` first."* and stop.
2. Read `.squad/roster.json`. If absent or no `active: true` roles: refuse with *"No active roles. Run `/cheeky-squad-os:squad-role` first."* and stop.
3. For each active role, read `.squad/role-goal-<role>.md` (its slice of the goal) — you derive the environment from it.

## Step 1 — Derive an environment for each role that lacks one

A role's `roster.json` entry MAY already carry an `environment` block. For each active role that does **not**, derive one from everything you know — the squad goal, the role goal, the role's `file_scope`, and its `tools`:

- **`workspace`** — `.squad/workspaces/<role>/`. This is the sandbox root.
- **`dirs`** — the working layout the role's job implies. A data puller wants `inputs/ outputs/ scratch/`; a report writer wants `drafts/ final/`. Keep it to what the role-goal's owned outputs need.
- **`env`** — only variables the role genuinely needs (e.g. an output dir, a locale, a model flag). Leave empty if none. Never put secrets here.
- **`context`** — local reference material the role should have at hand, as `{from, into, kind}`. `kind: "copy"` or `"link"` for in-project paths (contained, run locally). `kind: "fetch"` for anything off the network (this becomes a proposal, never auto-run).
- **`tools`** — derive from the role's `tools` allowlist + domain. For each: `{name, kind, verify, install?}`.
  - `kind: "local"` + an `install` that targets the sandbox (`pip install --target lib …`, `npm install --prefix …`, a binary dropped into `bin/`) → installed INTO the sandbox.
  - `kind: "system"` (a CLI like `jq`, `git`) or `kind: "mcp"` (an MCP server) → **never installed by you**; proposed to the user.

Write the derived block into the role's `roster.json` entry **via `squad-roster`** (it owns the file and re-validates). Do not hand-edit `roster.json`.

## Step 2 — Make the workspace writable by the role

For the in-sandbox boundary to be hook-enforced, each role's `workspace` must be inside its `file_scope` (otherwise the role's own Edit/Write into its sandbox would prompt). For every active role with an `environment`, ensure `<workspace>/**` is present in `file_scope`. If missing, add it **via `squad-roster`** and tell the user you widened the scope to cover the sandbox.

## Step 3 — Provision (dry pass first)

Run the provisioner **without `--install`** to materialize the contained, deterministic parts (dirs, `env`, local context) and to verify tool readiness:

```
${CLAUDE_PLUGIN_ROOT}/skills/squad-env/scripts/provision.sh .squad/roster.json .squad/goal.md
```

It emits one JSON line per role plus a final `{"summary": …}` line. Parse them. The summary carries:
- `global_needs` — everything that can't be contained (system/MCP tools missing, network fetches). Each is `{role, name, kind, hint}`.
- `local_plan` — the install commands for missing `kind: "local"` tools that *would* run inside the sandbox with `--install`.

## Step 4 — Present, then act on each tier

Show the user a short report:

```
Provisioned N role sandboxes:
  <role> → <workspace>  (dirs: D, context: C, tools ready: R)
  …

To finish locally (inside the sandbox, safe to run):
  <role>: <install cmd>          ← from local_plan
  …

Needs your decision (cannot be contained):
  <role>: <name> (<kind>) — <hint>     ← from global_needs
  …
```

Then:
- **Local plan** — this is contained autonomy. If `local_plan` is non-empty, run the provisioner once more **with `--install`** to execute those installs inside the sandboxes. (One action for the whole batch — not a prompt per tool.)

  ```
  ${CLAUDE_PLUGIN_ROOT}/skills/squad-env/scripts/provision.sh --install .squad/roster.json .squad/goal.md
  ```

- **Global needs** — never run these. Print the exact command for each (`brew install jq`, "enable MCP server X in settings", `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, etc.) and ask the user to handle them. If a need is a Claude Code setting (like the Agent Teams flag), you may offer to write it **with explicit consent in the same turn** (same rule `squad-spawn` uses for `settings.json`) — otherwise just surface it.

## Step 5 — Confirm

```
Squad environments provisioned.
  Sandboxes:   <list of workspace paths>
  Local installs run: <count> (or "none")
  Awaiting you: <count global_needs> (listed above, or "none")
The roles can now work inside their sandboxes — squad-spawn bakes each workspace
path and the env-source line into the spawn prompt.
```

## The workspace_block (for squad-role / role files)

When a role has an `environment`, its `.claude/agents/<role>.md` body gets this section (substituted for `{{workspace_block}}` in `templates/role-definition.md`). When it does not, `{{workspace_block}}` is omitted entirely:

```markdown
## Your workspace (sandbox)

You own a private sandbox at `<workspace>`. Work inside it freely — scaffolding
there (`mkdir`/`touch`/`cp`/`ln` with every path inside the sandbox) is
auto-approved, as are your Edit/Write calls there. Before running tooling, load
your environment:

    set -a; . <workspace>/env; set +a; <your command>

That puts your role-local `bin/` on PATH and sets your env vars — for this shell
only, never globally. Your seeded reference material is under the sandbox. If you
need a tool that isn't there, do not install it system-wide — surface the gap so
it can be added to your `environment` and provisioned.
```

## How this composes with the rest of the squad

- `squad-role` may call you to derive an `environment` for a role it just generated.
- `squad-spawn` calls you (or runs `provision.sh`) before dispatch, then bakes each role's workspace path + the env-source line into the spawn prompt.
- The `PermissionRequest` hook reads `environment.workspace` to auto-approve a running role's in-sandbox scaffolding. Keep `workspace` accurate or the hook will defer.

## Refusals

- **No goal:** refuse, point at `squad-onboard`.
- **No active roles:** refuse, point at `squad-role`.
- **Unsafe workspace** (absolute path, or `..` traversal): `provision.sh` skips it and reports an error; fix the role's `environment.workspace` (via `squad-roster`) before retrying. Never provision outside the project tree.
- **A `kind: "local"` install that does not target the sandbox:** treat it as a `global_need` and propose it — do not run an "install" that would touch the machine globally.

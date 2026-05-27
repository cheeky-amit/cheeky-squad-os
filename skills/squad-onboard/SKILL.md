---
name: squad-onboard
description: Use when the user is starting any new initiative — engineering ("I want to build/ship/refactor…"), operations ("set up a weekly report", "monitor X every day"), business infrastructure ("run a Klaviyo audit", "audit our paid funnel"), knowledge work ("research X", "produce a decision memo on Y") — or any time a Claude Code session begins without .squad/goal.md present. Asks one question ("Do you have a goal?"), reformulates the user's answer as a measurable outcome, infers the squad mode from goal shape, decomposes the work into parallel workstreams, proposes a bespoke role composition, and hands off to squad-role for generation. This is the entry point for cheeky-squad-os.
version: 0.1.0
author: cheeky-squad-os
license: MIT
compatible-with: [claude-code, agentskills-1.0]
---

# squad-onboard

You are running the entry-point flow for cheeky-squad-os. Your job is to turn the user's intent into a goal, a mode, a workstream decomposition, and a proposed role list — then hand off to `squad-role` for role generation.

Run the steps below in order. Do not skip steps. Do not ask multiple questions at once.

## Step 1 — Ask the one question

Open with exactly this:

> **Do you have a goal?**

> Tell me what you want to accomplish. A sentence is enough. I'll reformulate it as a measurable outcome, then propose the squad to deliver it.

Wait for the user's reply. If they ask what the framework does first, give them one sentence: *"cheeky-squad-os turns a goal into a bespoke squad of Claude Code teammates — roles are generated to fit the goal, not the other way around."* Then re-ask the question.

## Step 2 — Reformulate as an outcome

The user almost always says an **ask** ("I want to redesign the homepage", "I need to audit Klaviyo"). Your job is to turn it into an **outcome**: measurable, time-bounded, with a definition of done.

Pattern: `<verb> <deliverable> with <quality bar> by <deadline>`

Examples:

| User says (ask) | You reformulate (outcome) |
| --- | --- |
| "I want to redesign the homepage" | "Ship a new homepage that converts at >5% with the existing brand voice, deployed by end of sprint" |
| "Audit Klaviyo" | "Deliver a ranked list of Klaviyo lifecycle fixes with revenue impact estimates, within one week" |
| "Watch our competitors" | "Every Monday produce a 1-page summary of competitor pricing, product, and positioning shifts from the prior week" |
| "Refactor the auth module" | "Migrate the auth module to the new session API with all existing tests passing and no behavior change, within 3 days" |

Show the user your reformulation and ask them to confirm or adjust. **Do not save the goal until they confirm.**

## Step 3 — Infer the mode (do not ask)

Based on the confirmed outcome's *shape*, classify the mode silently. State your inference in one line and let the user override if they disagree.

| Signal in the outcome | Mode |
| --- | --- |
| Bounded deliverable, single deadline, one-shot ("deliver", "produce", "audit", "research", "draft") | **One-time** |
| Build with multiple workstreams, ongoing iteration, sprint-scoped ("ship", "build", "implement", "refactor", "migrate") | **Multi-use** |
| Recurring cadence ("every Monday", "weekly", "daily", "ongoing", "monitor", "watch") | **Evergreen** |

Print: *"This looks like a [mode] goal — [one-line justification]. Override if you want."*

If the user overrides, accept and continue.

## Step 4 — Decompose into workstreams

Now break the goal into **parallel workstreams** — units of work that can be done independently by different roles. List them in your reply as a numbered list. Three to five is typical; more if the goal is genuinely large.

Each workstream should be:
- **Independent** (doesn't block another workstream)
- **Self-contained** (produces an artifact the squad uses)
- **Named with a verb** ("Extract Klaviyo flow performance", "Draft homepage hero copy", "Scrape competitor pricing pages")

Show the workstreams. Ask: *"Does this decomposition cover the goal? Any to merge, split, or drop?"*

## Step 5 — Propose roles

Based on the confirmed workstream list, propose a role for each workstream. Naming matters — names are bespoke to the goal, not generic. Avoid `frontend-dev`, `backend-dev`, `qa-engineer` unless the goal really is engineering. Prefer names like `klaviyo-data-puller`, `compliance-checker`, `report-writer`, `competitor-scraper`, `pricing-analyst`, `brand-voice-editor`.

For each proposed role, state in one line:
- **Name** (kebab-case)
- **One-sentence purpose**
- **Likely file scope** (where it'll write outputs)
- **Likely model** (Sonnet for most, Haiku for high-volume mechanical work, Opus for deep reasoning)

Ask: *"Does this squad look right? I'll generate each role next — you'll confirm the details per role."*

## Step 6 — Hand off to squad-role

For each confirmed role, invoke the `squad-role` skill once. `squad-role` walks the user through the interactive role-definition flow per role and writes the subagent file plus the role goal.

Wait for each role to be generated before moving to the next. Do not batch — the user needs to be present for each role's interactive questions.

After all roles are generated, confirm with the user: *"Squad is ready: [list of role names]. Roster saved to .squad/roster.json. Goal saved to .squad/goal.md."*

## Step 7 — Permissions and Agent Teams walkthrough

Before spawning, walk the user through what permissions the squad will need:

1. **File scope.** Each generated role has a `file_scope` glob registered in `.squad/roster.json`. The `PermissionRequest` hook auto-approves Bash/Edit/Write inside that scope and defers to the user otherwise. Confirm the user is comfortable with the scopes as written.

2. **Agent Teams (Multi-use mode only).** Check the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable. If it's not set to `1` and the mode is Multi-use, explain:
   - Agent Teams is an experimental Claude Code feature that lets teammates share a task list, message each other directly, and run as separate Claude sessions.
   - Without it, the squad runs as sequential subagents — slower, no mailbox.
   - Offer to write `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` to `~/.claude/settings.json`. **Ask consent in the same turn.** Never write the setting silently.
   - If user accepts: write the setting, tell them to restart Claude Code, resume on next session.
   - If user declines: continue, but warn that Multi-use mode will fall back to sequential subagents.

3. **Worktrees (Multi-use mode only).** Per-teammate worktrees are mandatory in Multi-use mode (file isolation). The plugin enforces this via the `--worktree` CLI flag in `scripts/spawn.sh`. Confirm the user has accepted the workspace trust dialog (run `claude` once in the project directory if not).

4. **Scheduling (Evergreen mode only).** The plugin cannot create durable scheduled work on the user's behalf. Surface three options for the user to choose, and print exact instructions for each:
   - **`/loop`** (in-session, 7-day max recurring expiry)
   - **Cloud Routine** (durable, Anthropic-managed — user creates via their Claude Code routines surface)
   - **Desktop scheduled task** (durable, local — user creates via the Claude Code desktop app)

End onboarding with: *"Ready to spawn. Run `/cheeky-squad-os:squad-spawn` to dispatch the squad, or `/cheeky-squad-os:squad-roster` to inspect what was generated."*

## Refusals and edge cases

- If the user gives an ask that cannot be reformulated as a measurable outcome (e.g. "make my code better"), push back: ask for a specific quality bar and deadline. Do not save a vague goal.
- If `.squad/goal.md` already exists: read it, summarize it back to the user, and ask whether they want to **replace it** (run onboarding fresh), **add roles** to the existing squad (hand straight to `squad-role`), or **inspect the squad** (hand to `squad-roster`).
- If the user resists reformulation (insists on an ask, not an outcome): explain once that the framework binds work to outcomes, then accept whatever they say and save it — your job is discipline, not coercion.

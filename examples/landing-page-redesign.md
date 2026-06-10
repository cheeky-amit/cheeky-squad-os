# Worked example: homepage redesign with cheeky-squad-os

An engineering build, Multi-use mode. The team is "Acme B2B" — a small SaaS shop shipping a redesigned marketing homepage in one sprint.

## 1. The user's intent

Acme B2B's current homepage converts at 2.8%. Marketing and product have one sprint to ship a new one with a target north of 5%, while keeping the brand voice the editorial lead spent six months establishing. Four real workstreams: rewriting copy in-voice, designing the conversion-focused UX, building the component tree, and QA-ing against accessibility, performance, and A/B test gates. The lead engineer wants four agents working in parallel without stepping on each other's files.

## 2. Onboarding

```
User: /cheeky-squad-os:squad-onboard

squad-onboard: Do you have a goal?

User: redesign the homepage so it actually converts. Brand voice has to stay intact.

squad-onboard: Let me reformulate that as an outcome we can measure:

  "Ship a new homepage that converts at >5% with the existing brand voice,
   deployed by end of sprint."

  Does that match? If yes, what's the sprint end date?

User: yes — sprint ends 2026-06-10.

squad-onboard: Reading the shape of this work:
  - Multiple parallel workstreams (copy, design, build, QA)
  - Ongoing iteration inside a sprint (not a one-shot)
  - Each stream touches a different part of the repo

  This is Multi-use mode. Workstream decomposition:
    1. brand-voice-editor       — copy in-voice, gate before handoff
    2. conversion-ux-designer   — layout, flows, CTA hierarchy
    3. frontend-builder         — build the component tree, hit perf bars
    4. qa-runner                — verify against the DoD

  Save the goal and roster stubs?

User: yes.
```

## 3. Goal saved

`.squad/goal.md`:

```markdown
---
mode: multi-use
created: 2026-05-27T14:00:00Z
target: 2026-06-10
---

# Squad goal

Ship a new Acme B2B homepage that converts at >5% with the existing brand
voice intact, deployed to production by end of sprint (2026-06-10). The
lead engineer owns the squad and the final merge.

The current homepage converts at 2.8%. The redesign targets a >5% conversion
rate measured over a 7-day A/B test against the current page. Brand voice
(per `docs/brand-voice.md`) is non-negotiable — voice review must pass before
any copy ships to frontend.

## Definition of done

- Mobile Lighthouse Performance >= 90
- Desktop Lighthouse Performance >= 95
- axe-core: zero serious or critical violations
- A/B test against current homepage shows >= 5% conversion uplift over 7 days
- Brand voice review passes — copy reads in the established voice
- Deployed to production with kill-switch (instant rollback to current page)

## Out of scope

- Mobile native app — web only
- Internationalization — US English only
- Backend API changes — homepage is static + analytics only
```

## 4. Role generation

Four invocations of `squad-role`. Two shown in full; two as frontmatter only.

### Role 1: `brand-voice-editor` (full transcript)

```
User: /cheeky-squad-os:squad-role

squad-role: Which role from the roster stubs? (or "new")

User: brand-voice-editor

squad-role: One-line purpose?

User: write all homepage copy in the established brand voice; gate the final
      copy against the brand voice doc before frontend-builder uses it.

squad-role: Scoping. Three questions:
  1. File scope — paths this role reads AND writes?

User: copy/homepage/**, docs/brand-voice.md

squad-role:  2. Tools? (default: Read, Edit, Write, Glob, Grep)

User: Read, Write, Edit, Grep — no Bash, no Web.

squad-role:  3. Model? Heuristic: writing-heavy + voice judgment => opus.

User: opus.

squad-role: One more. What's the explicit handoff? Who reads its output,
            in what file, when is it "done"?

User: When approved, write final to copy/homepage/final/*.md and drop a
      HANDOFF.md there. frontend-builder reads only from final/.

squad-role: Generated. Writing .claude/agents/brand-voice-editor.md,
            .squad/role-goal-brand-voice-editor.md, and registering in
            .squad/roster.json.
```

Resulting `.claude/agents/brand-voice-editor.md` — frontmatter carries only name, description, tools, and model; the file scope is registered in `.squad/roster.json` and restated as body bullets:

```markdown
---
name: brand-voice-editor
description: Owns all homepage copy. Writes in the established Acme brand voice and gates the final copy against docs/brand-voice.md before frontend-builder consumes it.
model: opus
tools: Read, Write, Edit, Grep
---

# brand-voice-editor

Produce homepage copy — hero, sub-hero, three value props, social-proof
captions, pricing-teaser line, primary and secondary CTAs, footer tagline —
in the Acme brand voice as defined in `docs/brand-voice.md`.

File scope (mirrors `.squad/roster.json`):
- copy/homepage/**
- docs/brand-voice.md

Operating rules:
- Read `docs/brand-voice.md` before writing the first word.
- Iterate in `copy/homepage/drafts/`. Promote to `copy/homepage/final/`
  only after self-review against the voice doc.
- When you promote, write `copy/homepage/final/HANDOFF.md` with a changelog
  and the headline metric this copy is optimizing for.
- Do NOT write outside your file scope.
```

And `.squad/role-goal-brand-voice-editor.md` — the role's slice of the squad goal, which `squad-spawn` bakes into the spawn prompt:

> Write all homepage copy in the established Acme brand voice and gate it against `docs/brand-voice.md`, promoting approved copy to `copy/homepage/final/` with a `HANDOFF.md`, early enough in the sprint that frontend-builder can build and qa-runner can verify before 2026-06-10.
>
> **Owned outputs:** `copy/homepage/drafts/**`, `copy/homepage/final/**` (including `HANDOFF.md`).
>
> **Hand-offs:** frontend-builder — reads only from `copy/homepage/final/`; the `HANDOFF.md` is the "go" signal.

### Role 3: `frontend-builder` (full transcript)

```
User: /cheeky-squad-os:squad-role

squad-role: Which role?

User: frontend-builder

squad-role: Purpose?

User: build the homepage component tree from approved copy + design specs;
      handle responsive layout, accessibility, performance.

squad-role: File scope?

User: src/pages/homepage/**, src/components/homepage/**, public/homepage/**

squad-role: Tools?

User: Read, Write, Edit, Bash, Glob, Grep — needs Bash for the build.

squad-role: Model? Heuristic: typed component work + perf tuning => sonnet.

User: sonnet.

squad-role: Inputs — what does this role wait on?

User: copy/homepage/final/HANDOFF.md from brand-voice-editor, and
      design/homepage/specs.md from conversion-ux-designer. Don't start
      hero until both are in.

squad-role: Output handoff?

User: Tag "homepage-redesign-rc1" when lint + typecheck + local Lighthouse
      pass. qa-runner takes over from there.

squad-role: Generated. Writing .claude/agents/frontend-builder.md,
            .squad/role-goal-frontend-builder.md, and registering in
            .squad/roster.json.
```

Resulting `.claude/agents/frontend-builder.md` — again, scope lives in the roster, and the inputs/handoff answers landed in the role goal's Hand-offs, not in frontmatter:

```markdown
---
name: frontend-builder
description: Builds the Acme homepage component tree from approved copy and design specs. Owns layout, responsiveness, accessibility, and performance budgets.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
---

# frontend-builder

Turn approved copy and design specs into a shipping homepage that hits
Lighthouse Performance >= 90 mobile / >= 95 desktop and zero axe-core
serious/critical violations.

File scope (mirrors `.squad/roster.json`):
- src/pages/homepage/**
- src/components/homepage/**
- public/homepage/**

- Inputs: copy/homepage/final/HANDOFF.md (from brand-voice-editor) and
  design/homepage/specs.md (from conversion-ux-designer). Do not start
  hero work until both are present. Block and message the missing teammate.
- Component-level code only. No backend, no API routes.
- Run `pnpm lint && pnpm typecheck && pnpm lighthouse:local` before tagging
  `homepage-redesign-rc1`. qa-runner takes over from the tag.
```

And `.squad/role-goal-frontend-builder.md`:

> Build the homepage component tree from approved copy (`copy/homepage/final/`) and design specs (`design/homepage/specs.md`) into a page that passes Lighthouse >= 90 mobile / >= 95 desktop with zero serious axe-core violations, tagged `homepage-redesign-rc1` in time for QA before 2026-06-10.
>
> **Owned outputs:** `src/pages/homepage/**`, `src/components/homepage/**`, `public/homepage/**`.
>
> **Hand-offs:** qa-runner — picks up at the `homepage-redesign-rc1` tag.

### Role 2: `conversion-ux-designer` (frontmatter only)

Role goal (written to `.squad/role-goal-conversion-ux-designer.md`): "Design hero, social proof, pricing teaser, and CTA hierarchy; produce a spec frontend-builder can build directly from." Hand-off: frontend-builder reads `design/homepage/specs.md`. File scope (roster): `design/homepage/**`, `docs/conversion-patterns.md`.

```markdown
---
name: conversion-ux-designer
description: Owns the redesigned Acme homepage layout, conversion-focused flows, CTA hierarchy, and mobile-first design specs. Output is a spec frontend-builder builds from.
model: opus
tools: Read, Write, Edit, Glob, Grep
---
```

### Role 4: `qa-runner` (frontmatter only)

Role goal (written to `.squad/role-goal-qa-runner.md`): "Verify the shipped homepage against every DoD gate — Lighthouse, axe, cross-browser, A/B harness, kill-switch — and produce a pass/fail report." Starts at the `homepage-redesign-rc1` tag; hands `reports/homepage/qa-report.md` to the lead engineer. File scope (roster): `tests/homepage/**`, `reports/homepage/**`.

```markdown
---
name: qa-runner
description: Verifies the redesigned Acme homepage against every gate in the goal's Definition of Done. Produces a pass/fail report and blocks ship on any fail.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
---
```

After the four runs, `.squad/` holds the goal plus four role-goal files — `role-goal-brand-voice-editor.md`, `role-goal-conversion-ux-designer.md`, `role-goal-frontend-builder.md`, `role-goal-qa-runner.md` — which `squad-spawn`'s preflight requires before it will dispatch anyone.

## 5. The roster after generation

`.squad/roster.json`:

```json
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "multi-use",
  "created": "2026-05-27T14:10:00Z",
  "roles": [
    {
      "name": "brand-voice-editor",
      "purpose": "Write all homepage copy in the established Acme brand voice and gate the final copy before frontend-builder consumes it.",
      "agent_file": ".claude/agents/brand-voice-editor.md",
      "role_goal": ".squad/role-goal-brand-voice-editor.md",
      "file_scope": ["copy/homepage/**", "docs/brand-voice.md"],
      "tools": ["Read", "Write", "Edit", "Grep"],
      "model": "opus",
      "active": true,
      "created": "2026-05-27T14:10:00Z"
    },
    {
      "name": "conversion-ux-designer",
      "purpose": "Design the conversion-focused homepage layout, flows, and CTA hierarchy as a spec frontend-builder builds from.",
      "agent_file": ".claude/agents/conversion-ux-designer.md",
      "role_goal": ".squad/role-goal-conversion-ux-designer.md",
      "file_scope": ["design/homepage/**", "docs/conversion-patterns.md"],
      "tools": ["Read", "Write", "Edit", "Glob", "Grep"],
      "model": "opus",
      "active": true,
      "created": "2026-05-27T14:25:00Z"
    },
    {
      "name": "frontend-builder",
      "purpose": "Build the homepage component tree from approved copy and design specs to the Lighthouse and axe-core budgets.",
      "agent_file": ".claude/agents/frontend-builder.md",
      "role_goal": ".squad/role-goal-frontend-builder.md",
      "file_scope": ["src/pages/homepage/**", "src/components/homepage/**", "public/homepage/**"],
      "tools": ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
      "model": "sonnet",
      "active": true,
      "created": "2026-05-27T14:40:00Z"
    },
    {
      "name": "qa-runner",
      "purpose": "Verify the shipped homepage against every Definition-of-done gate and produce a pass/fail report.",
      "agent_file": ".claude/agents/qa-runner.md",
      "role_goal": ".squad/role-goal-qa-runner.md",
      "file_scope": ["tests/homepage/**", "reports/homepage/**"],
      "tools": ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
      "model": "sonnet",
      "active": true,
      "created": "2026-05-27T14:55:00Z"
    }
  ]
}
```

The four `file_scope` arrays are disjoint by construction — no path matches two roles — which is what lets the four worktree branches merge clean in §7.

## 6. Spawn (Multi-use path)

```
User: /cheeky-squad-os:squad-spawn

squad-spawn: Reading .squad/goal.md ... mode = multi-use.
             Checking env ... CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is unset.

  Multi-use mode runs each teammate as an Agent Teams member, which is
  experimental in Claude Code. Agent Teams adds:
    - a shared task list visible to every teammate
    - a per-teammate mailbox for direct messages
    - explicit teammate-to-teammate handoffs without going through the lead

  Without it, I fall back to sequential subagents — slower, no direct
  messaging, lead relays every handoff.

  I'd like to set:
    {"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}
  in ~/.claude/settings.json (merging, not overwriting). OK?

User: yes.

squad-spawn: Written. Restart Claude Code for the env var to take effect,
             then re-run /cheeky-squad-os:squad-spawn.
```

The user quits and reopens Claude Code. The SessionStart hook injects `.squad/goal.md` into the new lead session automatically. The user re-runs spawn.

```
User: /cheeky-squad-os:squad-spawn

squad-spawn: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 — good.
             Reading roster ... 4 active roles.
             Invoking ${CLAUDE_PLUGIN_ROOT}/skills/squad-spawn/scripts/spawn.sh ...

{"role":"brand-voice-editor","worktree":"/Users/acme/repo/.claude/worktrees/brand-voice-editor","branch":"squad-brand-voice-editor","status":"created"}
{"role":"conversion-ux-designer","worktree":"/Users/acme/repo/.claude/worktrees/conversion-ux-designer","branch":"squad-conversion-ux-designer","status":"created"}
{"role":"frontend-builder","worktree":"/Users/acme/repo/.claude/worktrees/frontend-builder","branch":"squad-frontend-builder","status":"created"}
{"role":"qa-runner","worktree":"/Users/acme/repo/.claude/worktrees/qa-runner","branch":"squad-qa-runner","status":"created"}
{"summary":{"created":4,"existed":0,"errors":0}}

squad-spawn: 4 worktrees pre-created. Spawning teammates (Agent Team) ...
```

After spawn, `git worktree list`:

```
$ git worktree list
/Users/acme/repo                                          a1b2c3d [main]
/Users/acme/repo/.claude/worktrees/brand-voice-editor     a1b2c3d [squad-brand-voice-editor]
/Users/acme/repo/.claude/worktrees/conversion-ux-designer a1b2c3d [squad-conversion-ux-designer]
/Users/acme/repo/.claude/worktrees/frontend-builder       a1b2c3d [squad-frontend-builder]
/Users/acme/repo/.claude/worktrees/qa-runner              a1b2c3d [squad-qa-runner]
```

The lead spawns each teammate into the Agent Team, referencing its `.claude/agents/<role>.md` by name and pointing it at the worktree `skills/squad-spawn/scripts/spawn.sh` pre-created. File isolation is anchored by each role's disjoint `file_scope` (the worktree is the working directory; the scope is the boundary). The spawn prompt baked into `brand-voice-editor`:

```
You are brand-voice-editor, a teammate on the Acme B2B homepage redesign squad.

=== GOAL (.squad/goal.md) ===
Ship a new Acme B2B homepage that converts at >5% with the existing brand
voice intact, deployed by end of sprint (2026-06-10).
[... full goal.md body ...]

=== YOUR ROLE (.claude/agents/brand-voice-editor.md) ===
Owns all homepage copy. Writes in-voice and gates the final copy against
docs/brand-voice.md before frontend-builder consumes it.

file_scope:  copy/homepage/**, docs/brand-voice.md
handoff:     copy/homepage/final/HANDOFF.md -> frontend-builder

=== YOUR FIRST TASK ===
1. Read docs/brand-voice.md end to end.
2. Draft hero, sub-hero, three value props, social-proof captions,
   pricing-teaser line, primary and secondary CTAs, footer tagline.
3. Self-review against the voice doc.
4. Promote to copy/homepage/final/ and write HANDOFF.md.
5. Ping frontend-builder via mailbox when done.

You are in worktree .claude/worktrees/brand-voice-editor (branch
squad-brand-voice-editor). You may only write files under your file_scope.
```

## 7. Parallel work + merge

Inside their worktrees:

- **brand-voice-editor** reads `docs/brand-voice.md`, drafts in `copy/homepage/drafts/`, self-reviews, promotes to `copy/homepage/final/`, writes `HANDOFF.md`, mails: `to: frontend-builder — copy final at copy/homepage/final/, headlines optimized for "specific pain + outcome" pattern.`
- **conversion-ux-designer** works concurrently — no input dependency. Produces `design/homepage/specs.md` with hero layout, three-card social-proof row, pricing teaser, dual CTA. Mails frontend-builder when specs land.
- **frontend-builder** opens its session, sees both inputs missing, blocks on its inbox. When both pings arrive, starts building. Runs `pnpm lint && pnpm typecheck && pnpm lighthouse:local`, all pass, tags `homepage-redesign-rc1`, mails qa-runner.
- **qa-runner** runs Lighthouse mobile + desktop, axe-core, Playwright cross-browser, wires the A/B harness, verifies the kill-switch toggles instantly. Writes `reports/homepage/qa-report.md` — all six DoD checks pass. Mails the lead.

The lead session, in the main checkout, sees four green mailboxes. Time to merge.

```
$ git checkout main
$ git merge squad-brand-voice-editor
Fast-forward
 copy/homepage/final/HANDOFF.md  | 18 ++++
 copy/homepage/final/hero.md     | 12 ++
 copy/homepage/final/value-props.md | 24 ++++
 copy/homepage/final/ctas.md     |  8 ++
 4 files changed, 62 insertions(+)

$ git merge squad-conversion-ux-designer
Fast-forward
 design/homepage/specs.md                   |  87 +++++++++
 design/homepage/wireframes/hero.md         |  41 +++++
 design/homepage/wireframes/social-proof.md |  33 +++
 3 files changed, 161 insertions(+)

$ git merge squad-frontend-builder
Fast-forward
 src/pages/homepage/index.tsx              | 142 +++++++++
 src/components/homepage/Hero.tsx          |  68 ++++
 src/components/homepage/SocialProof.tsx   |  54 +++
 src/components/homepage/PricingTeaser.tsx |  47 ++
 public/homepage/og-image.png              | Bin 0 -> 84211 bytes
 5 files changed, 311 insertions(+)

$ git merge squad-qa-runner
Fast-forward
 tests/homepage/lighthouse.spec.ts |  34 +++
 tests/homepage/a11y.spec.ts       |  28 ++
 tests/homepage/ab-harness.spec.ts |  52 +++
 reports/homepage/qa-report.md     |  91 +++++
 4 files changed, 205 insertions(+)
```

Zero conflicts. Each teammate's `file_scope` was non-overlapping by construction, so the four branches touched disjoint paths and merged clean.

## 8. What just happened

- Four bespoke roles for one specific build. No generic `frontend-dev` or `designer` — the names match the workstreams the goal actually decomposed into.
- Disjoint `file_scope` per role enforced file isolation. Each role declared its `file_scope` at generation time; `skills/squad-spawn/scripts/spawn.sh` pre-created a worktree per role as the working directory; the four branches merged without a conflict.
- Agent Teams was enabled with explicit consent. `squad-spawn` checked the env var, explained what Agent Teams adds, proposed the settings change, and only wrote `~/.claude/settings.json` after the user said yes.
- The goal traveled with the work. The SessionStart hook injected `.squad/goal.md` into the lead's session on restart, and `squad-spawn` baked the goal + per-role file into each teammate's spawn prompt — no teammate ever drifted off-mission.
- The lead did not manually relay handoffs. Teammates messaged each other directly through the Agent Teams mailbox; the lead only stepped in to merge at the end.

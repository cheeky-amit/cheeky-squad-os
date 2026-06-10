# Worked example — weekly competitive intel (Evergreen)

A recurring operational agent built with `cheeky-squad-os`. Three bespoke roles, one
durable cadence, one Monday-morning artifact.

## 1. The user's intent

Maya is the founder of a vertical-SaaS startup serving field-service businesses
(HVAC, plumbing, electrical). Every Monday she spends 90 minutes clicking through
her three main competitors' homepages, pricing pages, and blog indexes to figure
out what shipped, what re-priced, and what's being said about the category. She
wants the manual loop to stop. She wants a 1-page summary delivered every Monday
covering pricing changes, product launches, and positioning shifts from the prior
week, across her three competitors: **ServiceTitan**, **Jobber**, and
**Housecall Pro**. She doesn't want a dashboard, she doesn't want a tool, she
wants the brief in her inbox-equivalent — a markdown file she opens with coffee.

## 2. Onboarding (squad-onboard)

```
> /cheeky-squad-os:squad-onboard

squad-onboard:
  Do you have a goal?

> I want to stop checking what our competitors are doing every Monday by hand.
  Just deliver a summary.

squad-onboard:
  Let me reformulate that as an outcome you can verify each week:

    "Every Monday produce a 1-page summary of competitor pricing, product, and
     positioning shifts from the prior week, covering 3 named competitors."

  Two questions before I lock it in:
    1. Which 3 competitors?
    2. Anything explicitly out of scope (paid ads, social posts, hiring, etc.)?

> ServiceTitan, Jobber, Housecall Pro. Organic surfaces only — no ad spend,
  no LinkedIn posts. I just need the website + pricing + blog signal.

squad-onboard:
  Locked. Inferring mode from the language:
    - "Every Monday"           -> recurring cadence signal
    - "stop checking ... by hand" -> ongoing relief, not one-shot
    - no end-state target      -> indefinite

  Mode: EVERGREEN. Target: ongoing.

  Decomposing into workstreams:
    1. Scrape each competitor's homepage + pricing page + blog index (raw capture)
    2. Compare against prior week's snapshot, name the deltas (analysis)
    3. Write the 1-page Monday summary (synthesis)

  Proposed roles (you'll confirm each in squad-role):
    - competitor-scraper   — pulls structured snapshots of the 3 surfaces
    - signal-analyst       — diffs this week vs prior week, names what changed
    - summariser           — writes the 1-page founder-readable brief

  Writing goal.md. Run /cheeky-squad-os:squad-role next, three times.
```

## 3. Goal saved — `.squad/goal.md`

```markdown
---
mode: evergreen
target: ongoing
created: 2026-05-27
cadence: weekly (Mondays, 9am local)
---

# Goal

Every Monday produce a 1-page summary of competitor pricing, product, and
positioning shifts from the prior week, covering ServiceTitan, Jobber, and
Housecall Pro.

## Why this exists

The founder currently spends ~90 minutes every Monday clicking through three
competitor sites by hand. The summary replaces that loop. The brief is the
artifact the founder reads with coffee Monday morning to decide where to push
back in roadmap, pricing, and positioning calls that week.

## Definition of done (per iteration)

- Summary file written to `intel/summaries/<YYYY-MM-DD>.md` every Monday by
  9am local.
- Each of the 3 competitors covered in no more than 3 bullets.
- Deltas vs the prior week are explicit — not a restatement of current state.
- A closing "so what" line names the single most important signal for the
  founder that week.

## Out of scope

- Paid placements, ad spend, ad creative.
- Social posts (LinkedIn, X, TikTok, etc.).
- Hiring signals, press coverage, podcast appearances.
- More than 3 competitors per run — if a 4th becomes interesting, file a goal
  amendment, don't sneak it in.
- Dashboards, charts, or any non-markdown output.

## Competitors covered

1. ServiceTitan   — https://www.servicetitan.com
2. Jobber         — https://getjobber.com
3. Housecall Pro  — https://www.housecallpro.com

## Surfaces watched per competitor

- Homepage (hero copy, primary CTA, nav structure)
- Pricing page (tier names, prices, included features, billing model)
- Blog index (titles + publish dates from the prior 7 days only)
```

## 4. Role generation (squad-role)

### Role 1 — `competitor-scraper` (full transcript)

```
> /cheeky-squad-os:squad-role

squad-role:
  Reading .squad/goal.md ... mode is evergreen. I'll generate a role
  scoped to one of the three workstreams. Which role are we creating?

> competitor-scraper

squad-role:
  Good. Walking the role-spec questionnaire.

  Q1. One-sentence purpose. What does this role exist to do?

> Pull structured snapshots of each competitor's homepage, pricing page,
  and blog index for the past 7 days. Dump JSON the analyst can read.

squad-role:
  Q2. File scope. Where is this role allowed to write?
       (Tight scopes prevent role drift across iterations.)

> intel/competitors/raw/**

squad-role:
  Q3. Inputs. What does this role read before it writes?

> The list of competitor URLs from .squad/goal.md, plus the prior week's
  raw snapshot under intel/competitors/raw/ if it exists (for cache check).

squad-role:
  Q4. Tools. Pick the minimum set.
       Options: Read, Write, Bash, Grep, WebFetch, plus any MCP tools
       available (e.g. mcp__claude_ai_Fircrawl-Desktop__firecrawl_scrape,
       mcp__claude_ai_Fircrawl-Desktop__firecrawl_map).

> Read, Write, Bash, WebFetch.
  If Firecrawl is installed use firecrawl_scrape for the pricing page
  (it renders JS); fall back to WebFetch if Firecrawl is unavailable.

squad-role:
  Q5. Model. haiku / sonnet / opus?
       Heuristic: mechanical high-volume work -> haiku;
                  analysis/diff work          -> sonnet;
                  synthesis/writing           -> opus.

> haiku. This is mechanical fetch + parse + dump.

squad-role:
  Q6. Output contract. What shape is the artifact the next role consumes?

> One JSON file per competitor at
  intel/competitors/raw/<YYYY-MM-DD>/<competitor-slug>.json
  with keys: homepage_hero, pricing_tiers (array), blog_posts_last_7d (array).

squad-role:
  Q7. Failure mode. What does this role do when a surface 404s or times out?

> Write the JSON anyway with the field set to null and a note in a
  fetch_errors array. Never crash the run. The analyst handles partial data.

squad-role:
  Locked. Writing .claude/agents/competitor-scraper.md,
  .squad/role-goal-competitor-scraper.md, and registering in
  .squad/roster.json. Preview:
```

The agent file's frontmatter carries only name, description, tools, and model — the file scope is registered in `.squad/roster.json` (where the `PermissionRequest` hook reads it) and restated as body bullets:

```markdown
---
name: competitor-scraper
description: Pull structured weekly snapshots of competitor homepages, pricing
  pages, and blog indexes into intel/competitors/raw/<date>/<slug>.json
model: haiku
tools: Read, Write, Bash, WebFetch
---

# competitor-scraper

You exist to capture this week's structured snapshot of three competitor
surfaces. You do not analyze, you do not summarize — you fetch, parse, and dump.

File scope (mirrors `.squad/roster.json`):
- intel/competitors/raw/**

## Inputs

- Competitor list and URLs from `.squad/goal.md`
- Prior week's snapshot directory under `intel/competitors/raw/` if present

## Per-competitor procedure

1. Fetch the homepage. Extract the hero headline, sub-headline, and primary
   CTA text.
2. Fetch the pricing page. If Firecrawl is available, use
   `mcp__claude_ai_Fircrawl-Desktop__firecrawl_scrape` (the pricing pages render
   tiers via JS); otherwise WebFetch and parse what's there.
3. Fetch the blog index. Keep only posts published in the last 7 days.
4. Assemble JSON:

   ```json
   {
     "competitor": "<name>",
     "captured_at": "<ISO-8601>",
     "homepage_hero": { "headline": "...", "subhead": "...", "cta": "..." },
     "pricing_tiers": [{ "name": "...", "price": "...", "billing": "...",
                         "key_features": ["..."] }],
     "blog_posts_last_7d": [{ "title": "...", "url": "...", "published": "..." }],
     "fetch_errors": []
   }
   ```

5. Write to `intel/competitors/raw/<YYYY-MM-DD>/<slug>.json`.

## Failure handling

If a surface 404s or times out, write the JSON with the field set to `null`
and append a string to `fetch_errors` describing what failed. Never crash the
run — the analyst handles partial data.

## Out of scope

Do not analyze. Do not compare to prior weeks. Do not write to any path
outside `intel/competitors/raw/**`.
```

### Role 2 — `signal-analyst` (brief)

```
> /cheeky-squad-os:squad-role
> signal-analyst

squad-role:
  Locked after Q&A. Writing .claude/agents/signal-analyst.md ...
```

```markdown
---
name: signal-analyst
description: Diff this week's raw competitor snapshots against the prior week's
  snapshots; write a deltas file naming exactly what changed per competitor.
model: sonnet
tools: Read, Write, Grep
---

# signal-analyst

You exist to find what changed. You read two snapshot directories (this week and
last week) and produce a single deltas file that the summariser can synthesize.
You do not write the founder-facing summary; you produce the source of truth
for it.

File scope (mirrors `.squad/roster.json`):
- intel/competitors/deltas/**
```

### Role 3 — `summariser` (brief)

```
> /cheeky-squad-os:squad-role
> summariser

squad-role:
  Locked. Writing .claude/agents/summariser.md ...
```

```markdown
---
name: summariser
description: Read the week's deltas file; write the 1-page Monday brief at
  intel/summaries/<YYYY-MM-DD>.md, formatted for a founder's quick read.
model: opus
tools: Read, Write
---

# summariser

You exist to turn the analyst's deltas file into a brief Maya can read in three
minutes with coffee. One page. Three competitor sections, three bullets each
max. A closing "so what" line. No charts, no tables wider than what fits in a
terminal, no preamble. Be honest about low-confidence signals.

File scope (mirrors `.squad/roster.json`):
- intel/summaries/**
```

## 5. The roster after generation — `.squad/roster.json`

```json
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "evergreen",
  "created": "2026-05-27T10:00:00Z",
  "roles": [
    {
      "name": "competitor-scraper",
      "purpose": "Pull structured weekly snapshots of competitor homepages, pricing pages, and blog indexes into per-competitor JSON the analyst can read.",
      "agent_file": ".claude/agents/competitor-scraper.md",
      "role_goal": ".squad/role-goal-competitor-scraper.md",
      "file_scope": ["intel/competitors/raw/**"],
      "tools": ["Read", "Write", "Bash", "WebFetch"],
      "model": "haiku",
      "active": true,
      "created": "2026-05-27T10:00:00Z"
    },
    {
      "name": "signal-analyst",
      "purpose": "Diff this week's raw snapshots against the prior week's (reads competitor-scraper's output) and write the deltas file naming exactly what changed.",
      "agent_file": ".claude/agents/signal-analyst.md",
      "role_goal": ".squad/role-goal-signal-analyst.md",
      "file_scope": ["intel/competitors/deltas/**"],
      "tools": ["Read", "Write", "Grep"],
      "model": "sonnet",
      "active": true,
      "created": "2026-05-27T10:05:00Z"
    },
    {
      "name": "summariser",
      "purpose": "Turn the analyst's deltas file into the 1-page founder-readable Monday brief — runs last, after signal-analyst's hand-off.",
      "agent_file": ".claude/agents/summariser.md",
      "role_goal": ".squad/role-goal-summariser.md",
      "file_scope": ["intel/summaries/**"],
      "tools": ["Read", "Write"],
      "model": "opus",
      "active": true,
      "created": "2026-05-27T10:10:00Z"
    }
  ]
}
```

Run order is not encoded in the roster — there is no `depends_on` key. The
chain (`competitor-scraper → signal-analyst → summariser`) lives in each role's
purpose and role-goal hand-offs, and the dispatcher honors it at spawn time.

## 6. Spawn (squad-spawn) — Evergreen path

```
> /cheeky-squad-os:squad-spawn

squad-spawn:
  Reading .squad/goal.md ... mode is EVERGREEN.

  Evergreen mode means this squad runs on a recurring cadence — it is not a
  one-shot dispatch. I cannot create durable scheduled work on your behalf.
  Pick one of three scheduling options and I'll print the exact instructions:

  ┌─────────────────────────────────────────────────────────────────────────┐
  │ OPTION A — /loop  (in-session, up to 7-day expiry)                     │
  ├─────────────────────────────────────────────────────────────────────────┤
  │ Simplest. Runs inside the current Claude Code session. Per the          │
  │ scheduled-tasks docs, /loop has a 7-day max recurring expiry — you'll   │
  │ need to re-register it weekly (or pick B/C for durable).                │
  │                                                                         │
  │ Copy and run:                                                           │
  │                                                                         │
  │     /loop 1w dispatch the cheeky-squad-os squad against the current goal│
  │                                                                         │
  │ Good for: a 2-week pilot before you commit to durable infra.            │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │ OPTION B — Cloud Routine  (durable, Anthropic-managed)                 │
  ├─────────────────────────────────────────────────────────────────────────┤
  │ Survives session end. Runs on Anthropic's infrastructure. You create    │
  │ this yourself — I print the steps but I don't call the scheduler.       │
  │                                                                         │
  │ To set up a cloud routine for this squad:                               │
  │                                                                         │
  │   1. Note your squad goal location:                                     │
  │        /Users/maya/Projects/fieldserve-intel/.squad/goal.md             │
  │   2. Open your Claude Code routines surface                             │
  │        (CLI: `claude routines create`, or your dashboard)               │
  │   3. Create a routine with:                                             │
  │        - Schedule: 0 9 * * 1     (Mondays at 9am local)                 │
  │        - Prompt:   "dispatch the cheeky-squad-os squad against           │
  │                     .squad/goal.md"                                     │
  │        - Repository: <git remote URL of this project>                   │
  │   4. Save the routine ID somewhere you'll see it (e.g. append to        │
  │      .squad/roster.json under a `schedule` key).                        │
  │                                                                         │
  │ Good for: the v2, once the pilot proves the brief is useful.            │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │ OPTION C — Desktop scheduled task  (durable, local machine)            │
  ├─────────────────────────────────────────────────────────────────────────┤
  │ Runs on your laptop via the Claude Code desktop app. Only fires when    │
  │ your machine is awake — pick this only if your laptop is always on      │
  │ Monday morning.                                                         │
  │                                                                         │
  │ To set up a desktop scheduled task:                                     │
  │                                                                         │
  │   1. Open the Claude Code desktop app                                   │
  │   2. Settings -> Scheduled tasks -> New                                 │
  │   3. Fill in:                                                           │
  │        - Name:      "Weekly competitive intel"                          │
  │        - Schedule:  Weekly, Monday, 09:00                               │
  │        - Project:   <this project>                                      │
  │        - Prompt:    "dispatch the cheeky-squad-os squad against          │
  │                      .squad/goal.md"                                    │
  │   4. Save. The task fires next Monday at 9am.                           │
  │                                                                         │
  │ Good for: solo founder, one machine, no cloud-compute concerns.         │
  └─────────────────────────────────────────────────────────────────────────┘

  Which one do you want to start with? (You can change later — the squad and
  goal don't care which scheduler fires them.)

> A. Start with /loop for the pilot, I'll move to B in two weeks.

squad-spawn:
  Good. Run this now:

      /loop 1w dispatch the cheeky-squad-os squad against the current goal

  When it fires, the squad will run in this order:
      competitor-scraper -> signal-analyst -> summariser

  The output lands at intel/summaries/<YYYY-MM-DD>.md.
```

```
> /loop 1w dispatch the cheeky-squad-os squad against the current goal

/loop registered.
  Task ID:       loop-7f3a2c
  Interval:      1 week
  Next fire:     2026-06-01 09:00 local
  Expires:       2026-06-03 (7-day max — re-register before then)
  Prompt:        "dispatch the cheeky-squad-os squad against the current goal"
```

## 7. First Monday — the first iteration

Monday 2026-06-01, 09:00. The loop fires. The dispatch prompt executes against
`.squad/goal.md`. The roster runs in dependency order:

```
[09:00:02]  competitor-scraper  (haiku)   start
[09:00:11]  competitor-scraper            fetched servicetitan.com (3 surfaces, 0 errors)
[09:00:19]  competitor-scraper            fetched getjobber.com    (3 surfaces, 0 errors)
[09:00:26]  competitor-scraper            fetched housecallpro.com (3 surfaces, 1 error: blog index timeout)
[09:00:27]  competitor-scraper            wrote intel/competitors/raw/2026-06-01/{servicetitan,jobber,housecall-pro}.json
[09:00:27]  competitor-scraper            done

[09:00:28]  signal-analyst      (sonnet)  start
[09:00:28]  signal-analyst                reading raw/2026-06-01/ and raw/2026-05-25/ (prior week)
[09:00:44]  signal-analyst                computed deltas: 4 pricing, 3 product, 2 positioning
[09:00:45]  signal-analyst                wrote intel/competitors/deltas/2026-06-01.md
[09:00:45]  signal-analyst                done

[09:00:46]  summariser          (opus)    start
[09:01:08]  summariser                    wrote intel/summaries/2026-06-01.md (28 lines)
[09:01:08]  summariser                    done

[09:01:09]  squad run complete. Founder brief at intel/summaries/2026-06-01.md
```

### The artifact — `intel/summaries/2026-06-01.md`

```markdown
# Competitive intel — week of 2026-05-25 to 2026-05-31

*3 competitors. Organic surfaces only. Deltas vs the prior week.*

---

## ServiceTitan

- **Pricing** — moved Pro tier from per-user ($398/user/mo) to per-seat with
  a usage band ($349/seat/mo up to 50k jobs/yr, then metered). Enterprise
  tier price removed from page entirely; now "talk to sales" only.
- **Product** — homepage hero now leads with "AI Dispatch Copilot." No blog
  post backs it yet, so feature depth is unclear — could be a rename of
  existing scheduling, could be net-new.
- **Positioning** — hero copy shifted from "the #1 software for the trades"
  to "the AI platform for the trades." Sub-headline still emphasizes scale.

*Confidence: high on pricing (page diff is unambiguous), medium on the
AI Dispatch Copilot product claim (no supporting collateral yet).*

## Jobber

- **Pricing** — no change. Core ($69), Connect ($169), Grow ($349) all
  identical to prior week.
- **Product** — launched "Instant Payouts" — new feature noted on the
  pricing page Grow tier and announced in a blog post Tuesday 2026-05-27
  ("Get paid in seconds, not days"). Stripe-powered.
- **Positioning** — unchanged. Still "home service software your team will
  love."

*Confidence: high. Both the pricing-page badge and the blog post corroborate.*

## Housecall Pro

- **Pricing** — Essentials tier dropped from $79 to $69/mo. MAX tier price
  still on application. The drop looks like a direct response to Jobber's
  Core at $69.
- **Product** — no new product surface this week. (Blog index timed out
  during scrape — covered via cached titles only; no posts in the prior
  7-day window appear new.)
- **Positioning** — homepage hero unchanged. Footer added an "AI" link to
  a /ai landing page that didn't exist last week; page itself is thin
  (1 paragraph, marketing-only).

*Confidence: high on Essentials price drop, low on product (blog scrape
failed mid-run — re-verify next week).*

---

## So what

The category compressed on price this week. **Housecall Pro matched Jobber
at $69 on the entry tier**, and **ServiceTitan re-packaged Pro toward
usage-banded billing** — both moves point at the same pressure: the entry
buyer is shopping on monthly $ and a usage cap, not on seat count. If our
own pricing page still leads with per-user, that's the first place to look
this week.
```

The file is 28 lines of body. Maya opens it at 09:05 Monday with coffee. The
manual 90-minute loop is gone; the brief is the loop now.

## 8. What just happened — one-line lessons

- **Three roles, named for the actual work.** Not a generic "intel team" —
  `competitor-scraper`, `signal-analyst`, `summariser`. Each role has one
  output contract and one allowed path.
- **Evergreen mode bound the goal to a scheduler choice.** The plugin printed
  three options. The user picked `/loop` for the pilot. The user ran the
  command — the plugin did not.
- **The plugin doesn't own the schedule.** It owns the squad and the goal.
  The schedule lives wherever the user puts it: `/loop` for now, a cloud
  routine in two weeks, possibly a desktop task after that. Same squad, same
  goal, different fire mechanism.
- **Each Monday the same squad re-runs against the same `.squad/goal.md`.**
  No re-onboarding, no re-role-generation. The discipline is durable; the
  fire is durable; the artifact location is durable.
- **The hand-off surface is a file.** `intel/summaries/<date>.md`. The
  founder reads markdown, not a dashboard. Every iteration leaves a paper
  trail you can grep through six months later when you ask "when did
  ServiceTitan first lead with AI?"
- **"Run complete" is a summary, not a verdict.** The goal carries a
  per-iteration Definition of done; `/cheeky-squad-os:squad-verify` checks it
  (file written by 9am? ≤3 bullets per competitor? deltas explicit? "so what"
  line present?) and writes `.squad/verification.md`. Synthesis summarizes;
  verification decides.

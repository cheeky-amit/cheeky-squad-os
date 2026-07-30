# Worked Example: Klaviyo Lifecycle Audit

A walkthrough of using **cheeky-squad-os** to spin up a bespoke three-role squad for a one-week Klaviyo audit. This is agentic business infrastructure work — not engineering — and the squad is generated specifically for this goal. No generic team applied. Section 2 also walks guided domain research end to end: both human gates, one question the human cuts and one they add, one finding that comes back unanswered, a grade the human downgrades and a finding they drop, and the delta line that changes the decomposition before a single role is proposed. Section 10 shows the founder's `.squad/partner.md` — on file since her very first session with the plugin — changing three decisions a role made in this same run, without adding a single new file or metric.

---

## 1. The user's intent

A Shopify + Klaviyo brand owner runs a mid-size DTC store. Email used to drive 28% of revenue. Over the last six months it has flatlined around 19%. The owner has the gut feeling that the flows are leaking — wrong timing, wrong segments, maybe deliverability — but doesn't know where. She has one week before her board call. She installs `cheeky-squad-os` and opens Claude Code.

---

## 2. Onboarding (`/cheeky-squad-os:squad-onboard`)

```text
User: /cheeky-squad-os:squad-onboard

squad-onboard: Do you have a goal?

User: I think our Klaviyo flows are leaking revenue. Can you find the leaks?

squad-onboard: Let me reformulate that as an outcome so the squad
has something concrete to chase:

  "Deliver a ranked list of Klaviyo lifecycle fixes with revenue
   impact estimates per fix, within one week."

Does that match what you want?

User: Yes.

squad-onboard: Inferred mode: One-time.

Why: bounded deliverable (a ranked report), single deadline
(one week), no recurring trigger. When the report is delivered,
the squad's work is done. If you later want a monthly recurring
audit, that would be Evergreen — different dispatch path.

Want me to check the domain before I decompose?

  1. What's Klaviyo's current bulk-sender compliance threshold
     for bounce/complaint rate? (source: web search+fetch)
  2. Has list growth or list health changed materially in the
     last 90 days? (source: this codebase and project files)
  3. Is the welcome-flow open/click benchmark you've quoted
     before (~45%) still current? (source: web search+fetch)
  4. Anything already on record about known list-health issues?
     (source: a document you hand me)

Roughly 5-10 attended minutes, up to 4 source classes per
question. Say `skip` to decompose from what I already know, or
`go` to run this as written — or tell me what to cut or add
first.

User: Drop #4 — nothing written down. But add one: has anyone
already turned on Klaviyo's own deliverability monitoring for
this account? I don't want us proposing to build something that
already exists.

squad-onboard: Updated plan:

  1. What's Klaviyo's current bulk-sender compliance threshold
     for bounce/complaint rate? (source: web search+fetch)
  2. Has list growth or list health changed materially in the
     last 90 days? (source: this codebase and project files)
  3. Is the welcome-flow open/click benchmark you've quoted
     before (~45%) still current? (source: web search+fetch)
  4. Is Klaviyo's own deliverability monitoring already turned on
     for this account? (source: connected MCP tools — Klaviyo
     connector)

go?

User: go

squad-onboard: Running research — 4 questions, up to 4 sources
concurrently.

  1. [reported, web] Gmail/Yahoo's Feb-2024 bulk-sender rules cap
     complaint rate at 0.3%. Source: Google's bulk-sender
     guidelines page.
  2. [confirmed, codebase] reports/klaviyo/2026-02-audit-notes.md
     (a prior ad hoc check already in this repo) records list
     growth stalled at ~180K subscribers as of Feb 2026. Source:
     that file, read directly.
  3. Unanswered — no web source cites a benchmark specific enough
     to confirm or refute a ~45% figure for this SKU bracket;
     general email benchmarks range too widely to settle it.
  4. [confirmed, MCP] Account-level deliverability monitoring is
     currently off. Source: Klaviyo account-details tool read,
     2026-05-27.

Approve these — or tell me what to drop, correct, or downgrade.

User: Question 2's note — that was a contractor's guess, not a
verified pull. Downgrade it to reported. And drop #4; I turned
that monitor off on purpose months ago. It's not a finding, it's
a choice I made.

squad-onboard: Updated:

  1. [reported] Gmail/Yahoo Feb-2024 rule — 0.3% complaint cap.
  2. [reported] List growth stalled ~180K, per a contractor note
     (downgraded from confirmed at your request).
  3. Unanswered — welcome-flow benchmark; no source could confirm
     or refute it. Carried forward as a `needs:` for whichever
     role ends up quoting a benchmark number.

approve?

User: approve

squad-onboard: Written to .squad/world/claims-research.md.
Research changed the decomposition: +list-health workstream
(new), compliance re-anchored on the Feb-2024 0.3% Gmail rule.

Proposed workstreams:
  1. Extract — pull flow performance, list health, deliverability
     signals from Klaviyo (and cross-reference Shopify orders).
  2. List health — diagnose the stalled-growth signal before
     ranking anything downstream of it. (citing:
     klaviyo-list-growth-stalled-q1-2026)
  3. Analyze + rank — identify gaps, estimate revenue impact,
     surface compliance risks. Re-anchored on the confirmed
     complaint ceiling. (citing:
     gmail-bulk-sender-complaint-ceiling-0.3pct)
  4. Synthesize — write the final ranked report. (from priors)

Does this decomposition cover the goal? Any to merge, split, or
drop?

User: Merge list health into Extract — the data-puller already
pulls list-health metrics, it just needs to flag when they've
stalled. No need for a fourth role over one flag.

squad-onboard: Merged. Final workstreams:
  1. Extract — pull flow performance, list health (now flagging
     the stalled-growth signal from research), deliverability
     signals, and cross-reference Shopify orders. (citing:
     klaviyo-list-growth-stalled-q1-2026)
  2. Analyze + rank — identify gaps, estimate revenue impact,
     surface compliance risks, re-anchored on the confirmed
     complaint ceiling. (citing:
     gmail-bulk-sender-complaint-ceiling-0.3pct)
  3. Synthesize — write the final ranked report. (from priors)

Proposed roles (one per workstream):
  - klaviyo-data-puller    — pulls Klaviyo + Shopify data via MCP
  - compliance-checker     — flags deliverability/consent risks
  - report-writer          — synthesizes the ranked report

Handing off to squad-role to generate each role interactively.
```

---

## 3. Goal saved

`squad-onboard` writes `.squad/goal.md`:

```markdown
---
mode: one-time
created: 2026-05-27T09:00:00Z
target: 2026-06-03
---

# Squad goal

Deliver a ranked list of Klaviyo lifecycle fixes with revenue impact
estimates per fix, within one week. The audit covers all active
lifecycle flows (welcome, browse abandonment, cart abandonment,
post-purchase, winback, sunset) plus list health and deliverability.

## Definition of done

- Ranked list of >= 5 lifecycle fixes, ordered by estimated revenue impact
- Each fix has a revenue impact estimate (monthly $ or %)
- Each fix has a confidence score (low / medium / high) with rationale
- Compliance flags surfaced for any deliverability or consent risks
- Report delivered as a single markdown file at reports/klaviyo/final-report.md

## Out of scope

- Not implementing the fixes — recommendations only
- Not auditing SMS flows — email only
- Not redesigning templates — flow logic, timing, segments only
- Not touching production Klaviyo account — read-only data pulls
- Not quoting a revenue-impact number without naming the exact data point it
  rests on (from `.squad/partner.md`'s standing constraints)
```

That last bullet is the only line in this goal the founder did not state during
onboarding — `squad-onboard` read her existing `.squad/partner.md` silently at
Step 3 and pre-populated it from **Standing constraints** (hard rule #12),
attributed inline so it is never mistaken for a goal-specific exclusion. No new
question was asked to produce it; she had already said it, in an earlier
session, and it binds every squad this project ever runs. See section 10 for the
file itself and the three decisions it changed.

---

## 4. Role generation (`/cheeky-squad-os:squad-role`, one role at a time)

### Role 1: `klaviyo-data-puller`

```text
squad-role: What does this role do? (one sentence)

User: Pull Klaviyo flow performance, list health, deliverability
via MCP; dump as structured JSON for downstream roles.

squad-role: Role name (kebab-case)?

User: klaviyo-data-puller

squad-role: File scope (globs, comma-separated)?

User: data/klaviyo/**, reports/klaviyo/raw/**

squad-role: Tools? (Claude Code tool names and MCP tool patterns)

User: Read, Write, Bash, mcp__claude_ai_Klaviyo__*, mcp__claude_ai_Shopify__*

squad-role: Model? (sonnet / haiku / opus / fable / inherit, or a full model ID, e.g. `claude-opus-5`)

User: sonnet

squad-role: One-time mode — worktree isolation is off by default.
Confirm? (y/n)

User: y

squad-role: Generated .claude/agents/klaviyo-data-puller.md, wrote
.squad/role-goal-klaviyo-data-puller.md, and registered the role in
.squad/roster.json.
```

Generated `.claude/agents/klaviyo-data-puller.md` (frontmatter — scope is **not** frontmatter; it lives in `.squad/roster.json` and is restated as bullets in the agent body):

```yaml
---
name: klaviyo-data-puller
description: Pulls Klaviyo flow performance, list health, and deliverability data via MCP; cross-references Shopify orders; dumps structured JSON for downstream roles.
tools: Read, Write, Bash, mcp__claude_ai_Klaviyo__*, mcp__claude_ai_Shopify__*
model: sonnet
---
```

Generated `.squad/role-goal-klaviyo-data-puller.md` (outcome paragraph + hand-offs + stop conditions):

> Pull last-90-days flow performance for every active Klaviyo flow, list-level health metrics (growth, churn, engagement deciles), deliverability signals (bounce, complaint, open-rate by ISP), and cross-reference the same window of Shopify orders. Write everything as typed JSON to `data/klaviyo/` and a human-readable raw summary to `reports/klaviyo/raw/summary.md`. Do not interpret — just extract.
>
> **Hand-offs:** compliance-checker and report-writer — both consume `data/klaviyo/*.json` and `reports/klaviyo/raw/summary.md` from disk.
>
> **Stop conditions** (hard rule #14, derived by `squad-role` from this role's purpose, tools, and the goal's Out of scope):
> - `needs:` the Klaviyo MCP connector responds to a read call
> - `stop:` any API returns 403 twice

No belief-derived `stop:` bullet here, and that is the correct outcome rather than an omission: only a `confirmed` finding earns one, and the human downgraded both survivors to `reported` at Gate 2. A `reported` finding is context the role reads in the baked world index — it is not a bound the role self-polices. This is the ledger's discipline landing where it should: research that was downgraded binds nothing.

---

### Role 2: `compliance-checker`

```text
squad-role: What does this role do?

User: Read the Klaviyo data and flag any deliverability, consent,
or send-volume risks before rankings go out.

squad-role: Role name?

User: compliance-checker

squad-role: File scope?

User: reports/klaviyo/compliance/**

squad-role: Tools?

User: Read, Write

squad-role: Model?

User: sonnet

squad-role: Generated .claude/agents/compliance-checker.md, wrote
.squad/role-goal-compliance-checker.md, and registered the role in
.squad/roster.json.
```

Generated `.claude/agents/compliance-checker.md` (frontmatter):

```yaml
---
name: compliance-checker
description: Reads Klaviyo extraction output and flags deliverability, consent, and send-volume risks. Produces a compliance addendum that the report-writer must reference.
tools: Read, Write
model: sonnet
---
```

`.squad/role-goal-compliance-checker.md`:

> Read `data/klaviyo/*.json` and `reports/klaviyo/raw/summary.md`. Produce `reports/klaviyo/compliance/flags.md` listing every deliverability, consent, or send-volume risk: bounce rate > 2%, complaint rate > 0.1%, unsegmented sends to disengaged 180d+ subscribers, missing double-opt-in on EU-region growth sources. Each flag includes severity (low/medium/high) and the data point that triggered it.
>
> **Hand-offs:** report-writer — consumes `reports/klaviyo/compliance/flags.md`. This role starts only after klaviyo-data-puller's artifacts land.

---

### Role 3: `report-writer`

```text
squad-role: What does this role do?

User: Read the ranked fixes and compliance flags, write the final
ranked report with revenue impact estimates and confidence scores.

squad-role: Role name?

User: report-writer

squad-role: File scope?

User: reports/klaviyo/**

squad-role: That's broader than the other two — confirm? This
role is the synthesizer, so it needs read access to raw and
compliance and write access to the final report. (y/n)

User: y

squad-role: Tools?

User: Read, Write, Grep

squad-role: Model?

User: opus

squad-role: Effort? (optional — low / medium / high / xhigh / max;
omit to inherit the session's effort level)

User: xhigh — this role has to defend a dollar estimate per fix, want
the extra rigor on the reasoning.

squad-role: Generated .claude/agents/report-writer.md, wrote
.squad/role-goal-report-writer.md, and registered the role in
.squad/roster.json.
```

Generated `.claude/agents/report-writer.md` (frontmatter):

```yaml
---
name: report-writer
description: Synthesizes raw Klaviyo extraction and compliance flags into a ranked list of lifecycle fixes with revenue impact estimates and confidence scores. Produces the single deliverable.
tools: Read, Write, Grep
model: opus
effort: xhigh
---
```

`.squad/role-goal-report-writer.md`:

> Read `data/klaviyo/*.json`, `reports/klaviyo/raw/summary.md`, and `reports/klaviyo/compliance/flags.md`. Produce `reports/klaviyo/final-report.md`: a ranked list of >= 5 lifecycle fixes ordered by estimated monthly revenue impact. Each fix includes the impact estimate, a confidence score with rationale, the evidence (which data point or compliance flag triggered it), and a one-paragraph recommendation. Compliance issues marked high severity must appear in the top 3 regardless of revenue impact.
>
> **Hand-offs:** user — this is the last role in the chain; `reports/klaviyo/final-report.md` is the squad deliverable. Dispatch this role only after both upstream roles' artifacts land.
>
> **Stop conditions** (hard rule #14):
> - `needs:` "is the ~45% welcome-flow open/click benchmark still current?" is answered before this role commits — unanswered by research
> - `stop:` a fix's revenue estimate would rest on a benchmark number no source in `data/klaviyo/` supports

This is the third composition-loop mechanism landing. Research question 3 came back **unanswered** at Gate 2 — no source could confirm or refute the benchmark — and `squad-role` routed it to the one role whose work would quote a benchmark number. It is not backfilled with a guess, it is not silently dropped, and it does not gate dispatch. It surfaces at triage as a question only the human can close.

---

## 5. The roster after generation

`.squad/roster.json`:

```json
{
  "squad_goal_ref": ".squad/goal.md",
  "mode": "one-time",
  "created": "2026-05-27T09:30:00Z",
  "roles": [
    {
      "name": "klaviyo-data-puller",
      "purpose": "Pull Klaviyo flow performance, list health, and deliverability data via MCP and dump structured JSON for downstream roles.",
      "agent_file": ".claude/agents/klaviyo-data-puller.md",
      "role_goal": ".squad/role-goal-klaviyo-data-puller.md",
      "file_scope": ["data/klaviyo/**", "reports/klaviyo/raw/**"],
      "tools": ["Read", "Write", "Bash", "mcp__claude_ai_Klaviyo__*", "mcp__claude_ai_Shopify__*"],
      "model": "sonnet",
      "active": true,
      "created": "2026-05-27T09:30:00Z"
    },
    {
      "name": "compliance-checker",
      "purpose": "Read the Klaviyo extraction output and flag deliverability, consent, and send-volume risks before rankings go out.",
      "agent_file": ".claude/agents/compliance-checker.md",
      "role_goal": ".squad/role-goal-compliance-checker.md",
      "file_scope": ["reports/klaviyo/compliance/**"],
      "tools": ["Read", "Write"],
      "model": "sonnet",
      "active": true,
      "created": "2026-05-27T09:40:00Z"
    },
    {
      "name": "report-writer",
      "purpose": "Synthesize raw extraction and compliance flags into the ranked fix list with revenue impact estimates and confidence scores.",
      "agent_file": ".claude/agents/report-writer.md",
      "role_goal": ".squad/role-goal-report-writer.md",
      "file_scope": ["reports/klaviyo/**"],
      "tools": ["Read", "Write", "Grep"],
      "model": "opus",
      "effort": "xhigh",
      "active": true,
      "created": "2026-05-27T09:50:00Z"
    }
  ]
}
```

Note there is no dependency field in the roster — ordering is not roster data. The extract → check → synthesize sequence lives in each role goal's **Hand-offs** section, and `squad-spawn` reads those to sequence the dispatch: the writer goes last, after the auditor roles' artifacts land.

---

## 6. Spawn (`/cheeky-squad-os:squad-spawn`)

```text
User: /cheeky-squad-os:squad-spawn

squad-spawn: Mode = one-time. Preflight passed — goal, roster, all
three agent files and all three .squad/role-goal-*.md files present.

Dispatch triage (checkable `needs:` bullets only — the user may always
dispatch anyway):
  klaviyo-data-puller   starts: machine   (Klaviyo MCP connector responded to a read)
  compliance-checker    starts: machine   (no needs: declared)
  report-writer         starts: YOU       ("is the ~45% welcome-flow
                        open/click benchmark still current?" — unanswered
                        by research)

The role goals' Hand-offs sections imply a sequence — the data-puller's
artifacts feed the compliance-checker, and the report-writer reads both:

  1. klaviyo-data-puller
  2. compliance-checker    (consumes the data-puller's artifacts)
  3. report-writer         (consumes both upstream artifacts)

Dispatching klaviyo-data-puller now...
```

The Task prompt for `klaviyo-data-puller` (the only context channel from parent to subagent — both the squad goal and the role goal are baked in):

```text
You are the klaviyo-data-puller role for this squad.

=== SQUAD GOAL (.squad/goal.md) ===
Mode: one-time
Target: 2026-06-03

Deliver a ranked list of Klaviyo lifecycle fixes with revenue impact
estimates per fix, within one week. [...full goal body...]

Definition of done:
- Ranked list of >= 5 lifecycle fixes, ordered by estimated revenue impact
- Each fix has a revenue impact estimate (monthly $ or %)
- Each fix has a confidence score (low / medium / high) with rationale
- Compliance flags surfaced for any deliverability or consent risks
- Report delivered as a single markdown file at reports/klaviyo/final-report.md

Out of scope:
- Not implementing fixes — recommendations only
- Not auditing SMS — email only
[...]

=== YOUR ROLE GOAL (.squad/role-goal-klaviyo-data-puller.md) ===
Pull last-90-days flow performance for every active Klaviyo flow,
list-level health metrics (growth, churn, engagement deciles),
deliverability signals (bounce, complaint, open-rate by ISP), and
cross-reference the same window of Shopify orders. Write everything
as typed JSON to data/klaviyo/ and a human-readable raw summary to
reports/klaviyo/raw/summary.md. Do not interpret — just extract.

=== YOUR FILE SCOPE ===
You may Edit/Write within: data/klaviyo/**, reports/klaviyo/raw/**
Anything outside this scope will require explicit permission (the
PermissionRequest hook will defer).

=== TOOLS AVAILABLE ===
Read, Write, Bash, mcp__claude_ai_Klaviyo__*, mcp__claude_ai_Shopify__*

Begin work. Report back when done.
```

After `klaviyo-data-puller` finishes, file-scope outputs:

```text
data/klaviyo/flows-performance.json
data/klaviyo/list-health.json
data/klaviyo/deliverability.json
data/klaviyo/shopify-orders-90d.json
reports/klaviyo/raw/summary.md
```

`squad-spawn` then dispatches `compliance-checker` with the same prompt structure (squad goal + role goal + scope), reading the raw outputs. Then `report-writer` is dispatched last, reading both upstream artifacts.

After all three complete:

```text
reports/klaviyo/raw/summary.md
reports/klaviyo/compliance/flags.md
reports/klaviyo/final-report.md   <-- the deliverable
```

---

## 7. The deliverable

`reports/klaviyo/final-report.md` (excerpted):

```markdown
# Klaviyo Lifecycle Audit — Ranked Fixes

Window: 2026-02-26 to 2026-05-27 (90 days)
Account email revenue: $487K over window ($162K/mo avg)
Total subscribers: 184,302 | Engaged 30d: 41,118 (22.3%)

## Fix #1: Cart abandoner Flow — split the single 24h send into 1h + 24h + 72h
- **Estimated impact:** +$3,200/month
- **Confidence:** high
- **Evidence:** Current flow fires one email at 24h. Industry benchmark
  for the same SKU bracket recovers 8.4% of carts via a 3-touch series
  vs. 2.7% for single-touch (your current rate). Cart volume = 4,820/mo.
- **Recommendation:** Add a 1h reminder (no discount) and a 72h
  last-chance (5% offer, exclude high-AOV segment). Keep existing 24h.

## Fix #2: Compliance — bounce rate 3.1% on welcome series, kill the
  spreadsheet import segment
- **Estimated impact:** Prevents domain reputation collapse
  (unquantified $ — protective)
- **Confidence:** high
- **Evidence:** compliance-checker flagged bounce rate 3.1% on welcome
  Flow A (threshold 2%). Trace shows it's driven by a one-time CSV
  import on 2026-04-12 (12.4k addresses, never validated).
- **Recommendation:** Suppress the import segment, run it through
  re-engagement, then re-add only re-engagers.

## Fix #3: Post-purchase Flow — no review request between day 14 and day 30
- **Estimated impact:** +$1,900/month
- **Confidence:** medium
- **Evidence:** Repeat-purchase rate on customers who left a review is
  2.4× non-reviewers (Shopify cross-ref). Current flow ends at day 14
  with a thank-you. No review ask, no replenishment ask.
- **Recommendation:** Add a day-21 review request and a day-30
  replenishment offer for consumables.

## Fix #4: Browse abandonment — fires for everyone, including engaged 7d
- **Estimated impact:** +$1,400/month (margin-positive after suppression)
- **Confidence:** medium
- **Evidence:** Flow currently sends to anyone who views a product page
  and doesn't buy in 4h. 38% of triggers are engaged-7d subscribers who
  also receive the cart-abandoner. Open rates on overlapped sends are
  9% vs 24% baseline.
- **Recommendation:** Add a suppression filter for "received any flow
  email in last 48h" to reduce fatigue.

## Fix #5: Winback — single 90-day send, no 180/365 follow-up
- **Estimated impact:** +$900/month
- **Confidence:** medium
- **Evidence:** Winback at 90d recovers 1.1% of lapsed buyers. Brands
  with a 90/180/365 cadence in the same vertical recover 2.4%. Your
  lapsed pool = 22,400 buyers.
- **Recommendation:** Add 180d (educational, no discount) and 365d
  (final, 10% offer + sunset opt-down).

## Compliance addendum

- HIGH: Bounce 3.1% on welcome Flow A (see Fix #2)
- MEDIUM: 41% of EU subscribers acquired via spin-to-win without
  documented double-opt-in evidence
- LOW: Sunset flow exists but excludes the "Never engaged" segment

## Estimated combined monthly lift: ~$7,400/month
## Window to capture: 30 days post-implementation for #1, #3, #4, #5
```

---

## 8. What just happened — one-line lessons

- One bespoke squad for one specific goal. No generic team applied; the three roles only exist because this audit needed them.
- 3 roles, not 7. Sized to the work, not a default.
- Roles dispatched in dependency order. `report-writer` couldn't start until both upstream artifacts existed.
- File scopes are enforced by the `PermissionRequest` hook. In-scope writes auto-approve; an out-of-scope write — say `compliance-checker` reaching into `data/klaviyo/` — defers to the user for explicit approval. The hook never silently denies.
- The squad goal is injected into every spawn prompt (hard rule). Subagents have no other context channel from the parent — what's in the prompt is what they know.
- `SessionStart` and `UserPromptSubmit` hooks keep the goal in scope across the parent session too, so you never drift mid-audit.
- When the report ships, the squad is done. No recurring triggers, no scheduling. If the brand wants a monthly version next quarter, that's a new `squad-onboard` run in Evergreen mode — different dispatch path.

---

## 9. When a stop condition fires — the escalation beat

Sections 1–8 walked the clean run. Same squad, same roster, a harder day:
partway through `klaviyo-data-puller`'s pull, the Klaviyo API starts
returning 403 on the deliverability endpoint. This section walks the
escalation and evidence-bar machinery (hard rules #14–#15) end to end.

### 9.1 It fires

Two consecutive calls to `GET /api/metric-aggregates` (the bounce-by-ISP
breakdown, step 3 of the role's intended approach) return HTTP 403 — the
declared `stop: any API returns 403 twice` bound trips. `klaviyo-data-puller`
does not retry a third time and does not silently stop. It writes its own
engagement record with the escalation — the record's own file, nothing
else, is the hand-back:

```markdown
---
role: klaviyo-data-puller
created: 2026-05-27T10:00:00Z
status: escalated
fired: "any API returns 403 twice"
---

# Engagement record — klaviyo-data-puller

## Task read
Pull last-90-days flow performance, list health, deliverability, and
Shopify orders; dump structured JSON; do not interpret.

## Intended approach
1. Pull flow performance → data/klaviyo/flows-performance.json
2. Pull list health → data/klaviyo/list-health.json
3. Pull deliverability (bounce/complaint/open-rate by ISP) → data/klaviyo/deliverability.json
4. Pull Shopify orders (90d) → data/klaviyo/shopify-orders-90d.json
5. Write reports/klaviyo/raw/summary.md from all four

## Deliverables
- `data/klaviyo/flows-performance.json`
- `data/klaviyo/list-health.json`
- `data/klaviyo/deliverability.json`
- `data/klaviyo/shopify-orders-90d.json`
- `reports/klaviyo/raw/summary.md`

## Assumptions
- [reported] Klaviyo API key has read scope across all four endpoints — source: role goal / squad-role's tool grant.

## What happened
The `stop:` bound "any API returns 403 twice" fired on step 3 (pull
deliverability signals). Two consecutive calls to `GET
/api/metric-aggregates` for the bounce-by-ISP breakdown returned HTTP 403.
Steps 1–2 completed cleanly before this happened.

## State of the work
- `data/klaviyo/flows-performance.json` — complete
- `data/klaviyo/list-health.json` — complete
- `data/klaviyo/deliverability.json` — untouched
- `data/klaviyo/shopify-orders-90d.json` — complete (step 4 ran before the
  role stopped; steps are declared in order, not enforced sequentially)
- `reports/klaviyo/raw/summary.md` — partial: missing deliverability section

## What would unblock
Confirm the Klaviyo API key has the `metrics:read` scope (403 on this one
endpoint, 200 on the other three, points at a scope gap rather than a rate
limit) — or issue a fresh key. Once confirmed, re-dispatch this role;
everything else it produced stands and does not need re-pulling.
```

There is no `resolved` status this role could write instead, and no
`resolution:` field in the schema for it to add — see `templates/role-plan.md`.
Whether this is actually resolved is the human's call, made later, in a file
this role cannot reach.

### 9.2 `squad-verify` shows `met` blocked

`compliance-checker` and `report-writer` are held back — their role goals'
Hand-offs say they consume `klaviyo-data-puller`'s artifacts, and the
deliverability data never landed. Running
`/cheeky-squad-os:squad-verify` against the goal's Definition of done:

```markdown
---
verdict: partial
verified_at: 2026-05-27T11:00:00Z
goal_mode: one-time
signals_pass: 4
signals_fail: 0
signals_human: 1
escalations_open: 1
resolved_escalations: []
---

# Squad verification

## Signal: Compliance flags surfaced for any deliverability or consent risks

- **Status:** NEEDS-HUMAN
- **Evidence (machine):** `data/klaviyo/deliverability.json` does not exist —
  the source data was never pulled (see klaviyo-data-puller's engagement
  record, `status: escalated`).

<!-- the other four Definition-of-done signals read PASS; omitted here -->

## Escalations

### klaviyo-data-puller

- **Fired:** "any API returns 403 twice"
- **Blocks:** "Compliance flags surfaced for any deliverability or consent
  risks" — the signal's only source data is the deliverability pull that
  never landed.
- **Ruling:** UNRESOLVED

## Verdict

Partial. One signal blocked by an open escalation (see ## Escalations
above) — `met` is not available while `escalations_open > 0`. Resolve the
escalation, or grant a fresh Klaviyo key and re-dispatch
klaviyo-data-puller, then re-verify.
```

### 9.3 The human rules

The founder checks the Klaviyo dashboard directly and confirms: the key was
scoped to `campaigns:read` only, never `metrics:read`. She rotates the key,
`klaviyo-data-puller` is re-dispatched and completes cleanly this time. At
the next `squad-verify` run, she rules on the escalation itself — not by
editing the role's record (no role's write reaches `verification.md`; hers
doesn't either, by hand), but by answering `squad-verify`'s prompt:

```text
squad-verify: klaviyo-data-puller's escalation ("any API returns 403
twice") — has this been resolved, and how do you know?

Founder: Yes — the API key was scoped to campaigns:read only, not
metrics:read. Rotated the key on 2026-05-28, re-ran the pull, all four
data/klaviyo/*.json files are now present.
```

`squad-verify` records that verbatim, with attribution and date (hard rule
#15) — this is the only place it can be recorded:

```markdown
## Escalations

### klaviyo-data-puller

- **Fired:** "any API returns 403 twice"
- **Blocks:** "Compliance flags surfaced for any deliverability or consent
  risks" — the signal's only source data is the deliverability pull that
  never landed.
- **Ruling:** **Evidence (human attestation, 2026-05-28):** "The API key was
  scoped to campaigns:read only, not metrics:read. Rotated the key on
  2026-05-28, re-ran the pull, all four data/klaviyo/*.json files are now
  present." — founder
```

There is no `RESOLVED` tag and no status word invented for the ruling: the
quoted ruling **is** the record, and the frontmatter list is what actually
closes the escalation. That list gains:

```yaml
resolved_escalations:
  - klaviyo-data-puller
```

The two move together — a name in `resolved_escalations` with no ruling
written here, or a ruling here with no name added, is a malformed resolution
`squad-verify` flags rather than counts as closed.

### 9.4 Re-verify passes

With `data/klaviyo/deliverability.json` now on disk and the escalation
resolved, `compliance-checker` and `report-writer` dispatch. A final
`squad-verify` run recomputes `escalations_open = 1 − 1 = 0`. The signal
that was NEEDS-HUMAN now reads:

```markdown
## Signal: Compliance flags surfaced for any deliverability or consent risks

- **Status:** PASS (attested)
- **Evidence (human attestation, 2026-05-28):** "The API key was scoped to
  campaigns:read only, not metrics:read. Rotated the key, re-ran the pull,
  all four data/klaviyo/*.json files are now present."
```

`PASS (attested)` stays on the record permanently — it never quietly
becomes an ordinary machine `PASS`; anyone reading `verification.md` later
can tell a human closed this gap, not a script. With every signal PASS and
`escalations_open: 0`, the verdict is `met`, and `reports/klaviyo/final-report.md`
ships exactly as it does in section 7 — one day later than the clean run,
with an audit trail of exactly what went wrong and who signed off on the fix.

---

## 10. The partner model — three decisions it changed

This founder already has `.squad/partner.md` on disk, written in her very
first `cheeky-squad-os` session — `squad-onboard` read it silently this time,
no new question, no re-confirmation. Its standing constraint became the last,
inline-attributed bullet of the goal's Out of scope in section 3, and its full
body rode every spawn prompt in sections 6 and 9 alongside the goal and role
goal (hard rule #4):

```markdown
---
created: 2026-03-11T09:00:00Z
updated: 2026-03-11T09:00:00Z
---
# Partner model

## Decide vs. ask

Decide without me: report structure, formatting, and how to order or
weight competing findings — I'd rather see the finished call than be
asked to make it.
Always ask first: anything that would touch the live Klaviyo account,
even a read someone glancing at the account's activity log could mistake
for a change.

## Standing constraints

Never quote a revenue-impact number without naming the exact data point
it rests on — I've been burned once by a number that couldn't survive a
follow-up question from the board.

## Beliefs to check

I think our welcome-flow benchmark (~45% open/click) is still roughly
right, but I haven't rechecked it since we switched ESP-adjacent vendors
six months ago.
```

**Three decisions a role made differently because of it — not a new file, not
a new metric, the same run:**

1. **`report-writer` decided the report's structure without asking.** Its
   role goal (§4) states a hard trade-off with no obvious right answer: *"Compliance
   issues marked high severity must appear in the top 3 regardless of revenue
   impact."* Facing that call, a cautious role with no partner model might
   reasonably have escalated it as a judgment call for the founder. This one
   didn't need to — `Decide without me: … how to order or weight competing
   findings` put exactly this class of call outside the ask-first line, so
   Fix #2 (the compliance bounce-rate flag) sits at #2 in the final report
   (§7) ahead of two higher-dollar fixes, decided and shipped, never surfaced
   as a question.
2. **`report-writer` named the data point behind every dollar figure.** Look
   again at any `**Evidence:**` line under §7's fixes — cart volume, the
   exact benchmark comparison, the file the number traces to. The role goal
   (§4) only asked for "a confidence score with rationale," a thinner bar.
   The standing constraint — *never quote a revenue-impact number without
   naming the data point it rests on* — is what actually binds the report to
   that level of specificity, on every fix, not just the ones the role goal
   happened to spell out.
3. **`report-writer` reported back on the founder's own benchmark, instead
   of quoting it.** Her `Beliefs to check` entry is the ~45% welcome-flow
   open/click figure — the same thing research question 3 came back
   **unanswered** on at Gate 2 (§2), and the same thing `squad-role` turned
   into the role's `needs:` bullet that made triage print
   `starts: YOU — report-writer` (§6). Baked into the prompt as a
   belief-to-check, it stopped being a number to reuse and became a thing to
   test. The role tested it against `data/klaviyo/` and could not settle it,
   so it ended its run with one line back to the orchestrator —
   `[belief-check: welcome-flow open/click benchmark ~45% is still roughly
   right] could not test — nothing in data/klaviyo/ measures open/click at
   the flow level for this window` — which `squad-spawn`'s per-spawn
   synthesis printed to the founder verbatim, in the role's own words rather
   than a paraphrase. The visible consequence is what
   is **missing** from §7: no fix in the final report quotes a welcome-flow
   benchmark percentage. Without the partner model that ~45% was a figure
   the founder had used before and a role would have inherited as settled;
   with it, the report routes around a number nobody could stand behind and
   the founder learns her six-month-old assumption is still untested.

A partner model assembled by inference would have guessed at all three of
these and gotten at least one wrong. This one didn't guess — the founder said
all three lines herself, in an earlier session, and `squad-partner` wrote
down exactly what she said.

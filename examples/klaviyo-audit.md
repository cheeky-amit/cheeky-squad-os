# Worked Example: Klaviyo Lifecycle Audit

A walkthrough of using **cheeky-squad-os** to spin up a bespoke three-role squad for a one-week Klaviyo audit. This is agentic business infrastructure work — not engineering — and the squad is generated specifically for this goal. No generic team applied.

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

Proposed workstreams:
  1. Extract — pull flow performance, list health, deliverability
     signals from Klaviyo (and cross-reference Shopify orders).
  2. Analyze + rank — identify gaps, estimate revenue impact,
     surface compliance risks.
  3. Synthesize — write the final ranked report.

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
```

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

squad-role: Model? (sonnet / haiku / opus)

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

Generated `.squad/role-goal-klaviyo-data-puller.md` (outcome paragraph + hand-offs):

> Pull last-90-days flow performance for every active Klaviyo flow, list-level health metrics (growth, churn, engagement deciles), deliverability signals (bounce, complaint, open-rate by ISP), and cross-reference the same window of Shopify orders. Write everything as typed JSON to `data/klaviyo/` and a human-readable raw summary to `reports/klaviyo/raw/summary.md`. Do not interpret — just extract.
>
> **Hand-offs:** compliance-checker and report-writer — both consume `data/klaviyo/*.json` and `reports/klaviyo/raw/summary.md` from disk.

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
---
```

`.squad/role-goal-report-writer.md`:

> Read `data/klaviyo/*.json`, `reports/klaviyo/raw/summary.md`, and `reports/klaviyo/compliance/flags.md`. Produce `reports/klaviyo/final-report.md`: a ranked list of >= 5 lifecycle fixes ordered by estimated monthly revenue impact. Each fix includes the impact estimate, a confidence score with rationale, the evidence (which data point or compliance flag triggered it), and a one-paragraph recommendation. Compliance issues marked high severity must appear in the top 3 regardless of revenue impact.
>
> **Hand-offs:** user — this is the last role in the chain; `reports/klaviyo/final-report.md` is the squad deliverable. Dispatch this role only after both upstream roles' artifacts land.

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

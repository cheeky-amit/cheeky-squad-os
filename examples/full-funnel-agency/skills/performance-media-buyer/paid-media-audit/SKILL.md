---
name: paid-media-audit
description: Use before taking over or restructuring an inherited ad account, and quarterly thereafter — a structural pre-flight across account architecture, bidding, budget, targeting, and creative coverage that runs before any spend decision is made.
---

# paid-media-audit

Source: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-auditor.md

Adapted from that agent's 200-plus checkpoint audit framework. Two changes were made on
purpose.

**It was split.** The source audits structure *and* measurement in one pass. In this
squad those are two seats, so this skill keeps only the structural half — architecture,
bidding, budget, targeting, creative coverage. Every tracking, tagging, attribution, and
conversion-counting checkpoint was removed and lives in the tracking-analyst's
[`conversion-tracking-audit`](../../tracking-analyst/conversion-tracking-audit/SKILL.md).
Running both is the full original; running one twice is waste.

**It was cut to what changes a decision.** 200 checkpoints is a deliverable in search of
a reader. What survives below is the set where a failing check has a named consequence
and a first action. If a check cannot fail loudly, it was dropped.

## Order of operations

Run top to bottom. Each section can invalidate the ones after it — there is no point
grading creative coverage inside a campaign structure you are about to collapse.

### 1. Architecture

- Campaign count versus conversion volume. A campaign earning fewer than ~30
  conversions in 30 days cannot support its own bid strategy — flag for consolidation.
- Naming convention: can you tell channel, funnel stage, and audience from the name
  alone? If not, every downstream report is manual.
- Brand and non-brand isolated? Mixed, brand's efficiency masks non-brand's cost.
- Duplicate or overlapping targeting between campaigns competing in the same auction.
- Geographic and schedule settings that were set once and never revisited.

### 2. Bidding

- Every automated strategy: is it past its learning period, and did anything reset it?
  Frequent target edits keep a campaign learning forever.
- Targets that were set against a conversion definition that has since changed. This is
  the one check that requires a word with the tracking-analyst before you grade it.
- Manual bidding surviving anywhere with enough volume to automate.
- Portfolio strategies spanning campaigns with genuinely different economics.

### 3. Budget

- Budget-constrained campaigns: limited by budget while hitting efficiency targets is
  the cheapest finding in any audit — name the daily amount and the observed headroom.
- Spend concentration: what share sits in the single largest campaign, and does that
  match its share of results?
- Pacing shape over the last 28 days — front-loaded, flat, or erratic, and why.
- Spend on elements with no conversions in 60 days, totalled in currency, not percent.

### 4. Targeting and audiences

- First-party audiences uploaded but never applied, or applied in observation mode where
  targeting was intended.
- Exclusions: existing customers, recent purchasers, and current employees excluded from
  prospecting.
- Negative coverage on search: how much spend went to queries nobody would have bought.
- Audience overlap across social campaigns that are bidding against each other.

### 5. Creative coverage

- Any ad group or ad set running a single active asset — no test is possible there.
- Assets live longer than 8 weeks with declining click-through. Hand these to the
  creative-strategist as a refresh request, do not rewrite them here.
- Extension and asset types eligible but unpopulated.
- Message continuity between ad and landing page: does the promise on the ad appear
  above the fold on the page?

## Grading

Three severities only. More granularity than this gets argued about rather than fixed.

- **Critical** — costing money now, or blocking a goal signal. Fix this week.
- **Structural** — will cost money as spend scales. Fix before the next budget increase.
- **Note** — true, worth knowing, not worth a sprint.

Every finding, without exception, carries: the observation, the money or signal at
stake, the first action, and who does it. A finding without a first action is an opinion.

## Output

Write to `deliverables/media/audit-<account>-<YYYY-MM-DD>.md`: findings grouped by
severity, then one "first five moves" list at the top — ordered, each with an owner.
The client brief quotes that list, not the body.

## Constraints

- **Never propose a promotional offer, discount, or price change as a fix.** It is out
  of scope for this program regardless of how well it would perform.
- Do not grade tracking here. If a structural finding depends on a conversion definition,
  say so and route it — a wrong number makes a confident finding worse than no finding.

## Done when

- Every section above has been run, or is explicitly marked not-applicable with a reason.
- Every finding has severity, stake, first action, and owner.
- The first five moves are ordered and owned.

## Provenance & limits

Sources searched: anthropics/skills (no match), addyosmani/agent-skills (no match), msitarzewski/agency-agents (paid-media-auditor.md — this skill, structural half only; its measurement half went to tracking-analyst), obra/superpowers (no match), web search for paid-media audit checklists (several vendor lead-magnet checklists, none attributable). Execution dimension for this seat was researched separately and produced google-ads-operations.
Intake date: 2026-08-15
Known limits: Platform-neutral by design, which means it names no specific setting or report — a practitioner still has to know where to look. Says nothing about tracking, deliberately (see the scope boundary). The severity scale has three levels because more gets argued about rather than fixed; an account large enough to need finer triage would outgrow it.
Assumed superseded: this skill reflects what research found at intake, not the best way that exists. Re-run `squad-roster`'s Refresh-skills operation periodically rather than treating this as final.

---
name: organic-search-brief
description: Use before proposing any new page, title, heading, or on-page change for organic search — runs the cannibalization check and cluster-ownership map first, so no brief steals a query a live page already ranks for.
---

# organic-search-brief

Source: https://github.com/msitarzewski/agency-agents/blob/main/marketing/marketing-seo-specialist.md

Adapted from that agent's cannibalization-prevention and content-strategy rules. The
source covers technical crawl health, link authority, and page experience alongside
content; all three were dropped here because they are site-engineering work this squad
does not own and cannot ship. What was kept is the one part that is pure marketing
judgement and the most frequently skipped: **deciding which page owns which query,
before writing anything.**

The source states the cannibalization check as a mandatory precondition. That framing is
correct and is preserved literally — it is step 1 below, and no brief exists until it has
been run.

## Step 1 — the cannibalization check (mandatory, no exceptions)

Before proposing any title, heading, page, or content change:

1. Pull search-console data for the target queries, by page and by query, over 90 days.
2. For each target query, identify which page currently earns the most impressions and
   clicks. **That page owns that query.** Ownership is observed, not assigned.
3. Look for split signals: two or more pages ranking in the top 20 for the same query
   with clicks divided between them. That is active cannibalization and it gets fixed
   before anything new is written.
4. Write the ownership map into the brief. If the check cannot be run — no data access,
   a brand-new site — say so explicitly and mark the brief `unverified`. Do not proceed
   quietly as though the check passed.

## Step 2 — the cluster map

One pillar page per topic; satellites answer narrower questions that the pillar links to
and that link back.

- Each page has **one** primary query it owns and a small set of secondary queries it
  may rank for incidentally.
- A satellite may never target its pillar's primary query, in its title, its main
  heading, or its opening paragraph.
- If a proposed page has no query the existing set does not already own, it is not a new
  page — it is an update to an existing one. Say that instead.

## Step 3 — the brief

```markdown
# Organic brief: <working title>

**Primary query:** <query> — currently owned by <page URL or "unowned">
**Search intent:** informational | commercial | transactional | navigational
**Cluster:** <pillar URL> — this page is: pillar | satellite
**Cannibalization check:** run <date> — <what it found>

## Why this page can win
<What it will answer that the current top results do not. If the honest answer
is "the same thing, better written", say so — that is sometimes true and
sometimes the reason not to write it.>

## Must answer
- <the questions a reader arrives with, in the order they arrive>

## Evidence required
- <the data, demonstration, or first-hand detail that makes it credible;
  a page with none is a summary of other pages>

## Internal links
- From: <existing pages that will link here, with the anchor text>
- To: <pages this must link to>

## Not this page's job
- <the adjacent queries owned by siblings, named, so the writer does not drift>
```

## Rules

1. **Intent before volume.** A high-volume query whose intent the page cannot satisfy is
   a ranking that will not convert and will not hold.
2. **The "Not this page's job" section is required.** Drift into a sibling's query is how
   a cluster cannibalizes itself six months later, one honest paragraph at a time.
3. **No claim without evidence in the brief.** Same standard as the paid creative brief —
   if the claim cannot be substantiated at brief time, it does not go in the outline.
4. **No promotional, discount, or price-led angles.** The program's constraint applies to
   organic content as it does everywhere else.
5. **White-hat only.** Nothing that trades on manipulating rankings rather than being the
   better answer.

## Coordination

Category-education topics briefed here often deserve a video slot too. Hand the topic to
the creative seat's
[`organic-social-plan`](../../creative-strategist/organic-social-plan/SKILL.md) with the
primary query attached, rather than letting a page and a video get written independently
about the same question in different words.

## Output

Write to `deliverables/lifecycle/organic/<slug>.md`. Keep the ownership map in
`deliverables/lifecycle/organic/cluster-map.md` and update it whenever a page's owned
query changes — the map is the thing that keeps the check cheap next time.

## Done when

- The cannibalization check has been run and its result is in the brief, or the brief is
  marked `unverified` with a reason.
- The primary query has exactly one owning page after this brief ships.
- The "Not this page's job" section names the adjacent queries.
- Every claim in the outline has its evidence named.

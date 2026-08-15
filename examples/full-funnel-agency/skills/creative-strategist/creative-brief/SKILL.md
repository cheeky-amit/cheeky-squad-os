---
name: creative-brief
description: Use when a hook-matrix cell is ready for production — turns one cell into a brief a designer, editor, or writer can execute end to end without asking a follow-up question.
---

# creative-brief

Source: https://github.com/msitarzewski/agency-agents/blob/main/marketing/marketing-content-creator.md

Adapted from that agent's content strategy and multi-format production guidance. The
source covers a wide surface — editorial calendars, brand storytelling, repurposing,
distribution. Most of that is planning, and this squad plans in the hook matrix. What
was worth keeping is the production discipline: the specificity that separates a brief
someone can execute from a brief that generates three clarifying questions and a day of
delay.

So this is narrowed to one job — **one matrix cell becomes one shippable spec** — and
tightened everywhere the source was directional.

## Precondition

A brief starts from a cell id that already exists in the hook matrix and is marked
`planned`. If there is no cell, there is no brief: go write the hypothesis first. This
is the single rule that keeps production from quietly becoming the strategy.

## The brief

```markdown
# Brief: <cell-id> — <working title>

**Cell:** <cell-id> (hypothesis lives in the matrix; do not restate it here)
**Placement:** <exact platform, exact placement, exact ratio and duration>
**Due:** <date> — flight starts <date>

## The one thing
<A single sentence: what a viewer must take away. If two sentences are needed,
the cell is testing two things and should be split.>

## Must contain
- <element> — <why it is non-negotiable: a claim substantiation, a legal line,
  a product state that must be visible>

## Must not contain
- <element> — <why>

## Shape
- **First 2 seconds / above the fold:** <what is on screen or on the page,
  concretely — not "attention-grabbing opener">
- **Middle:** <the demonstration or evidence that carries the claim>
- **Close:** <the action, stated the way the landing page states it>

## Copy
- Primary: <exact text, within the placement's character limit>
- Headline: <exact text>
- Alternates: <2-3, varying only the element under test>

## Continuity
- Landing page: <URL>
- The promise on this asset appears on that page as: <the exact line>

## Assets and rights
- <source files, product units, footage, music licence status>

## Reviewers
- <name> — <what they are approving, and by when>
```

## Rules

1. **Exact beats descriptive.** "9:16, 1080x1920, under 20 seconds, hook on frame 1" is
   a spec. "Vertical short-form, punchy" is a mood.
2. **Character limits are checked in the brief, not in the platform.** A headline that
   truncates on delivery is a failed test, not a failed asset.
3. **Message continuity is a required field.** If the promise on the asset does not
   appear on the landing page, the test measures the page, not the creative.
4. **Alternates vary one element.** Three alternates that differ in every line produce
   one result and no learning.
5. **Never brief a discount, promotional offer, sale, or price-based claim.** The program
   forbids it; a brief containing one gets rejected at review and costs a cycle.
6. **Substantiate every claim in the brief itself.** A performance claim carries its
   source next to it, or it does not go in the asset.

## Handling a rejected review

Rejections come back to the brief, not to the asset. Amend the brief, note the change
under the reviewer's line, and re-issue with the same cell id. Amending the asset while
the brief still says something else is how two versions of the truth start circulating.

## Scope boundary

This skill does not decide what to test, does not set kill or scale criteria, and does
not read results — all three belong to [`hook-matrix`](../hook-matrix/SKILL.md). It also
does not plan organic distribution; see
[`organic-social-plan`](../organic-social-plan/SKILL.md).

## Done when

- The brief names a real cell id.
- Every copy field is exact text within its limit.
- The continuity line quotes an actual line on the actual page.
- Every reviewer has a name and a date.

---
name: hook-matrix
description: Use when planning a creative flight or deciding what to test next — lays out hook x audience x format as a matrix where every cell is a written hypothesis with a kill or scale criterion attached before anything is produced.
---

# hook-matrix

Source: https://github.com/msitarzewski/agency-agents/blob/main/paid-media/paid-media-creative-strategist.md

Adapted from that agent's creative testing and RSA architecture frameworks. The source
is right about the central claim — when the platform controls bids, budget, and
targeting, creative is the remaining lever, and every asset is a hypothesis. What it
leaves implicit is where the hypothesis is *written down*. In practice it never is, and
a month later nobody can say what a concept was testing or whether it worked.

This skill makes the matrix the artifact. Assets are produced from cells. Results are
read back into cells. A concept that never had a cell does not get a budget.

## The three axes

**Hook** — the claim or tension the first two seconds carry. Not a headline; the reason
someone stops. Five to eight per flight, no more. Each must be falsifiable: "this
audience does not know the difference is measurable" is a hook you can be wrong about.

**Audience** — who the hook is aimed at, defined by what they already believe, not by
demographics. "Owns the entry-level version and suspects it is the bottleneck" is an
audience. "25-44, urban" is a targeting setting.

**Format** — the execution shape: static, short-form video, carousel, comparison,
demonstration, customer-voice. Format is a variable, not a wrapper — the same hook in
two formats is two cells and two results.

## The cell

Every populated cell is one file, or one row, carrying exactly this:

```markdown
### <hook-id> x <audience-id> x <format>

- **Cell id:** H3-A1-VID
- **Hypothesis:** <audience> will act on <hook> because <the belief being
  exploited or corrected>.
- **Primary signal:** <the one metric that reads this hypothesis — usually
  the shallowest one that is still causal: hold rate for a hook test,
  click-through for a claim test, cost per acquisition only for a full-funnel
  test>
- **Kill criterion:** <threshold> after <spend or impressions>, whichever
  comes first.
- **Scale criterion:** <threshold> sustained over <window>.
- **Reads on:** <date the cell becomes readable>
- **Status:** planned | live | killed <date> | scaled <date>
```

## Rules that keep the matrix honest

1. **Kill and scale criteria are written before production**, not after results arrive.
   A criterion chosen after the fact always confirms the concept.
2. **Never fill the whole matrix.** Five to eight hooks against three audiences and four
   formats is 96 cells; a flight runs 8 to 12. Choosing which cells is the strategic
   work — say why each was chosen and what it rules out.
3. **One variable per comparison.** Two cells that differ in hook *and* format teach you
   nothing about either.
4. **The shallowest causal signal wins.** Judging a hook on cost per acquisition means
   waiting three weeks to learn something a hold-rate read answers in four days.
5. **A killed cell is a result, not a failure**, and its hypothesis line is the thing
   worth keeping. Killed cells stay in the file.
6. **No cell may propose a discount, promotional offer, or price-based claim** — this
   program's brand constraint rules it out, so a cell built on one is unrunnable no
   matter how it would perform.

## Reading results back

Weekly, against reconciled numbers only:

- Mark each live cell against its own criteria — not against the others. Comparative
  ranking comes after, and only among cells that shared an audience.
- A cell that hit neither criterion by its read date is **inconclusive**, and gets one
  extension or is killed. It never gets a third.
- When a hook wins in two formats against the same audience, promote the *hook* to the
  next flight's anchor and vary everything else around it.
- Winners hand off to [`organic-social-plan`](../organic-social-plan/SKILL.md) — organic
  runs concepts paid has already paid to validate.

## Scope boundary

This skill decides what to test and how it will be judged. It does not specify how the
asset gets made — that is [`creative-brief`](../creative-brief/SKILL.md), which starts
from a cell id and never restates the hypothesis.

## Done when

- Every planned cell has a hypothesis, a primary signal, both criteria, and a read date.
- No two live cells differ by more than one variable within an audience.
- Every killed and scaled cell has a date and stays in the file.

# Organic brief: Burr alignment and uneven espresso extraction

**Author:** lifecycle-organic-marketer · **Skill:** `organic-search-brief` · **Written:** 2026-08-22

**Primary query:** `burr alignment espresso` — currently **unowned**
**Search intent:** informational, with commercial follow-through
**Cluster:** `/guides/coffee-grinder-burrs` (pillar) — this page is a **satellite**
**Cannibalization check:** run 2026-08-21 against 90 days of search-console data, page × query. **Result below — it found a blocker on a different query, and that blocker is being fixed first.**

---

## Step 1 — the cannibalization check

Ran before anything was written. Target queries and their current owners:

| Query | Impressions (90d) | Owning page | Ownership |
|---|---|---|---|
| `burr alignment espresso` | 1,240 | — | **unowned** — no page in the top 20 |
| `grinder burrs uneven extraction` | 890 | — | unowned |
| `coffee grinder burrs` | 4,310 | `/guides/coffee-grinder-burrs` | clear, 68% of clicks |
| `burr material guide` | 1,120 | `/blog/burr-material-guide` | clear |

**Blocker found, on a query this brief does not target.** `coffee grinder burr replacement`
(2,180 impressions) is split between the pillar (94 clicks, position 6.2) and
`/blog/burr-material-guide` (63 clicks, position 8.8). Both in the top 20, clicks divided:
that is active cannibalization.

Per the skill, that gets fixed before anything new is written. **Fix, agreed with Dana
2026-08-22:** the pillar owns `coffee grinder burr replacement`; the blog post's H1 and
title drop "replacement" and re-anchor on material comparison, which is what it actually
answers. Raised as a separate change; **this brief is not blocked by it**, because the query
it targets is unowned and untouched by the fix.

## Step 2 — the cluster map

- **Pillar:** `/guides/coffee-grinder-burrs` — owns `coffee grinder burrs`, `coffee grinder burr replacement`.
- **This satellite:** owns `burr alignment espresso`, and may incidentally rank for `grinder burrs uneven extraction`.
- **Sibling:** `/blog/burr-material-guide` — owns `burr material guide`, `conical vs flat burrs` after the fix above.

The cluster map in this directory was updated with these three ownership rows on
2026-08-22, so the next brief's check starts from the map rather than re-querying 90 days.

## Step 3 — the brief

### Why this page can win

The current top results answer "what is burr alignment" as a specification. None of them
starts from the symptom the searcher actually has — one side of the shot running faster —
and none shows the diagnosis. We have bench footage and a repeatable test procedure, which
is first-hand evidence the incumbents do not have.

### Must answer, in the order a reader arrives with them

1. Why does one side of my shot run faster than the other?
2. How do I tell alignment from grind size, tamp, or a worn basket?
3. How do I check alignment myself, without buying anything?
4. What do I do if it is out of true?
5. When is it the grinder rather than the alignment?

### Evidence required

- The 2026-06 bench test — 12 pulls, same dose and setting, before and after alignment.
  This is the page's reason to exist; without it the page is a summary of other pages.
- Photographs of a burr set out of true against a straightedge.
- The marker test procedure, written as steps a reader can follow with what they own.

### Internal links

- **From:** `/guides/coffee-grinder-burrs` — anchor "alignment"; `/guides/burr-life` — anchor "uneven extraction".
- **To:** `/guides/coffee-grinder-burrs` (pillar), `/parts/finder`.

### Not this page's job

- `coffee grinder burr replacement` — the pillar owns it. Do not use "replacement" in the
  title, H1, or opening paragraph.
- `conical vs flat burrs` — the sibling's after the fix.
- `burr life` / when to replace — `/guides/burr-life` owns it.

## Constraints

No promotional, discount, or price-led angle. White-hat only: this page competes by being
the better answer, and the evidence section is where that is won or lost.

## Coordination

The same topic is cell **H3-A1-VID** in [`../../creative/hook-matrix.md`](../../creative/hook-matrix.md),
and the video's landing page is `/guides/burr-alignment` — which is this page. Handed the
primary query to `creative-strategist` on 2026-08-22 so the page and the video say the same
thing in the same words rather than being written independently about the same question.

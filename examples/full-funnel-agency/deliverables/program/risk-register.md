# Program risk register — Kettleworks

**Owner of this file:** studio-producer · **Skill:** `program-risk-register`
Append-only within the program. Closed rows stay — a closed row is the evidence the response worked.
**Last reviewed:** 2026-08-24

---

## R1 — Meta access never arrives, and a third of spend stays manual

- **Trigger:** the Meta Marketing API MCP server is still unconnected on **2026-09-07** (three weeks in).
- **Impact if it fires:** $34,800 per 28 days — 29% of tracked spend — stays on a manual apply loop. Every Meta change lands a day late, which breaks the 28-day comparison the whole pacing method rests on. Directly threatens the acquisition-cost signal.
- **Owner:** Dana
- **Pre-agreed response:** stop staging Meta changes weekly and move that row to a fortnightly cadence, so at least the comparison windows are clean. Tell the client the same day, in the brief, with the cost stated in days of delay.
- **Status:** open. This is the declared capability gap on `performance-media-buyer`'s role goal; the two are the same fact tracked in two places for two audiences.

## R2 — the tracking fix waits on a team the squad does not control

- **Trigger:** the deduplication key is not on the Meta browser event by **2026-09-04**.
- **Impact if it fires:** Meta prospecting stays unreconciled. Under the pacing rule, an unreconciled row cannot carry a spend decision, so the largest single spend line stays frozen — not because it is performing, but because nobody can prove what it is doing.
- **Owner:** Kettleworks web lead (raised 2026-08-19 by tracking-analyst)
- **Pre-agreed response:** escalate to the client's engineering manager with the phantom-order count in plain terms — 178 orders in 28 days that do not exist — and ask for a named date, not a priority.
- **Status:** open, fired-risk watch. Raised 2026-08-19, no date returned yet as of 2026-08-24.

## R3 — spend is committed ahead of trustworthy measurement

- **Trigger:** any week where tracked spend rises above $118,400 while overall variance is above 3%.
- **Impact if it fires:** the program spends more into a number it cannot verify. Every dollar added while variance is at 16% buys results the squad cannot attribute, and the acquisition-cost signal becomes unauditable at exactly the moment it matters.
- **Owner:** studio-producer
- **Pre-agreed response:** hold spend flat and say so in the brief. This is the response, decided now, while nobody is under pressure — and it is the reason week 1's pacing review moved nothing.
- **Status:** open. Not fired: spend held at $118,400 this week.

## R4 — one channel carries too much of the program

- **Trigger:** any single row exceeds 35% of tracked spend for two consecutive windows.
- **Impact if it fires:** concentration risk. Meta prospecting is at 29.4% ($34,800 of $118,400) and is simultaneously the worst-performing row and the one the squad cannot operate directly.
- **Owner:** performance-media-buyer
- **Pre-agreed response:** cap the row at its current budget and route incremental spend to whichever row has a `budget` constraint and two reconciled windows under target.
- **Status:** open, not fired — 29.4%, below the 35% trigger.

## R5 — creative approval sits on the critical path

- **Trigger:** any flight brief waits more than 48 hours for reviewer approval.
- **Impact if it fires:** flights slip a week each time, and the goal needs 12 concepts shipped with recorded criteria. Four are live; the arithmetic does not tolerate many slipped weeks.
- **Owner:** Dana
- **Pre-agreed response:** brief on a two-reviewer rule with a named deputy, and ship on the deputy's approval when the primary is silent past 48 hours.
- **Status:** open, not fired — H3-A1-VID's brief was approved inside 6 hours on 2026-08-19, including one amendment round. One data point is not a pattern; this row closes if the trigger stays unfired through 2026-09-07.

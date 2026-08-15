---
name: lifecycle-sequence-spec
description: Use when designing, fixing, or reviewing any automated email or SMS sequence — welcome, browse abandon, cart abandon, post-purchase, winback — so it cannot ship without a trigger, a segment definition, exit conditions, and a click-based success bar.
---

# lifecycle-sequence-spec

Source: https://github.com/msitarzewski/agency-agents/blob/main/marketing/marketing-email-strategist.md

Adapted from that agent's sequence design spec and its critical rules. The source is
strong and opinionated, and four of its rules are carried through intact because they
are correct and routinely violated: segmentation over broadcast, respect the lifecycle,
clicks over opens, and exit conditions are non-negotiable.

Three changes were made. The source is written for long-sales-cycle service businesses —
its lifecycle stages and its benchmark set were re-anchored on a direct-to-consumer
purchase cycle. Its platform-specific detail was dropped, because it dates fast and this
squad's platform is a project fact, not a skill fact. And its measurement section was
narrowed to a single pass bar, so a sequence review ends in ships or does not ship.

## The spec

No sequence ships without every field below filled. A blank field is a blocker, not a
to-do.

```markdown
## <Sequence name>

### Trigger
- Event: <the observable event or state change>
- Delay: <immediate | X hours | X days after the trigger>
- Suppression: <who is excluded at entry, and why>

### Segment
- Entry definition: <at least two attributes — lifecycle stage plus one of
  behaviour, recency, value tier, or channel consent>
- Estimated size: <count at the time of writing, with the date>

### Messages
| # | Channel | Delay from entry | Job of this message | Primary link |
|---|---------|------------------|---------------------|--------------|

### Exit conditions
- <converted — name the event>
- <unsubscribed or opted out>
- <hard bounce or delivery failure>
- <entered a higher-priority sequence>
- <max duration reached — every sequence has one>

### Success bar
- Primary: <click-through or click-to-open threshold>
- Secondary: <revenue per recipient, or completion rate>
- Reads on: <date>

### Compliance
- Consent basis: <how these contacts consented, recorded where>
- Sender and reply path: <marketing sender, never the transactional one>
```

## The four rules carried from the source

1. **Never broadcast.** Every send targets a segment defined by at least two attributes.
   One attribute is a report, not a segment.
2. **Respect the lifecycle.** A recent purchaser never receives an acquisition sequence.
   A churned contact never receives a post-purchase request. Sequence membership reflects
   where a contact is now, not where they were at capture.
3. **Clicks over opens.** Open rates are inflated by privacy-preserving mail clients and
   cannot carry a decision. Judge on click-through, click-to-open, and revenue per
   recipient. An open rate may appear in a report only as directional context.
4. **Exit conditions are non-negotiable.** Every sequence names all five above. A
   sequence with no maximum duration will eventually mail someone forever.

## Added for this program

5. **No discount, promotional offer, coupon, or sale language in any message.** The
   program's brand constraint applies to lifecycle exactly as it applies to ads. Where a
   source template's default winback or cart sequence leans on an incentive, replace the
   incentive with the reason the product is worth the consideration — that is the harder
   craft problem and the whole point of the constraint.
6. **Deliverability is a precondition, not a metric.** Before any sequence expands its
   audience: sender authentication in place, complaint rate under the platform's hard
   limit with margin, hard bounces removed on detection. A sequence scaled onto a
   damaged sender reputation damages every other sequence too.
7. **One primary link per message.** A message with four competing links has no
   measurable job.

## Reviewing an existing sequence

Read it against the spec and report only what is missing or wrong, in this order: exit
conditions, segment definition, lifecycle violations, success bar, then copy. The order
matters — a beautifully written sequence with no exit condition is the more urgent
problem, and copy notes crowd out structural ones if they come first.

## Output

Write to `deliverables/lifecycle/sequences/<sequence-name>.md`. Amend the same file when
the sequence changes; keep a dated changelog at the bottom so a performance shift can be
matched to a change.

## Scope boundary

This skill designs the system that delivers the message. It does not write the on-page
content that earns organic traffic — see
[`organic-search-brief`](../organic-search-brief/SKILL.md) — and it does not decide paid
creative angles, which come from the creative seat's hook matrix. Where a lifecycle
message reuses a validated paid angle, cite the cell id rather than re-deriving it.

## Done when

- Every field in the spec is filled.
- All five exit conditions are named, including a maximum duration.
- The success bar is click-based and has a read date.
- No message contains promotional, discount, or price-led language.

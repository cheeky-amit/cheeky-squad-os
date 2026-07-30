---
name: squad-partner
description: Use when the human wants to record, view, change, or remove the standing brief that describes how they want to work with this squad — phrases like "set up my partner model", "here's how I want you to work with me", "decide that without me next time", "always ask before X", "no vendor mentions ever, that's a standing rule", "check whether I'm right that X", "show my partner model", "update the partner model", "delete the partner model". Manages `.squad/partner.md` — one per project, describing the single commanding human, not the initiative. Verbs: create (drafts from the conversation so far, then at most 3 skippable questions), show, update (diff → confirm → bump `updated`), delete (requires typing `yes, delete`).
version: 0.1.0
author: cheeky-squad-os
license: MIT
allowed-tools: [Read, Write, Edit, Bash]
compatible-with: [claude-code, agentskills-1.0]
---

# squad-partner

Every other skill in this plugin writes what a role or a flow decided. `squad-world`'s `claims-user.md` is the human authoring their own beliefs about the world; this skill is the human authoring the brief on *themselves* — the second and last place in cheeky-squad-os where the human is the artifact's own author, not a delegate acting for them (`CONTRIBUTING.md`'s skill-count rule).

`.squad/partner.md` is the plugin's answer to desideratum 1, "You understand me" (Collins et al. §2.3): the human's decide-vs-ask line, the constraints that bind every squad in this project, and the beliefs of theirs a role should check rather than inherit.

## Hard rule #12 — told, not inferred

`.squad/partner.md` contains **only statements the human confirmed in the same turn they were written.** `squad-partner` is the file's only writer, anywhere in this plugin. It holds no third parties and no secrets. The plugin never observes, infers, or accumulates a fact about the human into this file — every sentence in it was dictated, not deduced.

A partner model assembled by inference is a dossier. This one is a brief the human dictates, sentence by sentence, and every sentence was confirmed as it went in. If a draft you propose contains anything the human hasn't actually said this turn, cut it before writing — do not carry it forward "because it seemed implied."

**No third parties, no secrets — and that is a check you run, not a claim you make.** Before any write, on **every** verb that writes (`create` and `update`), read the body you are about to write and hold each line against two tests: does it characterize a *person other than the human* (a named colleague, a client, a founder, "my CTO is slow to reply"), and does it carry a *secret* (an API key, a token, a password, an unlisted URL)? A line that fails either test does not go in, even when the human dictated it and is happy to have it written — the file is gitignored by **default**, not by mechanism, so a sentence about someone who never consented is one declined ignore-line offer away from living in version control. Say which line and why, offer the version that keeps the instruction and drops the third party (*"always ask before I reassign anyone's work"* instead of naming them) or points at where the secret lives instead of quoting it, and write the rewritten line only once the human confirms it in the same turn like any other. If they insist on the original, do not write it here: say plainly that this file is the wrong home for it.

## File schema

```markdown
---
created: <ISO-8601 datetime>
updated: <ISO-8601 datetime>
---
# Partner model

## Decide vs. ask

## Standing constraints

## Beliefs to check
```

Exactly these three sections, in this order — no more, no fewer. `templates/partner.md` carries the full annotated schema and a worked example; read it before drafting.

**Why three, and not more:**

- **Decide vs. ask** — "Decide without me:" and "Always ask first:" lists. Changes what a role *surfaces* instead of silently settling. May carry attention lines ("batch questions, one block per session") and a deadline tie-break for when an ask-first item collides with a deadline.
- **Standing constraints** — invariants that bind every squad in this project, the way `.squad/goal.md` binds one squad.
- **Beliefs to check** — hypotheses the human holds that a role must *verify* rather than inherit as settled fact. A role that touches one reports back **confirmed / contradicted / could not test**. This is the direct answer to the paper's "possibly false beliefs."

**Two sections were cut on purpose and must never come back:**

- `## Expertise` — self-graded and never checked against a consequence; theatre, not signal.
- A standalone `## Attention budget` — over-structures a file that should stay well under a hundred lines. Its two load-bearing lines (batching, deadline tie-break) live as attention lines inside **Decide vs. ask** instead.

If a human asks for either back, say why it was cut and offer the merged form instead — don't silently add a fourth section.

## Privacy — a default offer, not a mechanism

`.squad/partner.md` is a model of a person, living in a git repo; the source paper (§5.3) flags models of humans as dual-use. This plugin does not make the file private by any enforced mechanism — it offers to keep it out of git, once, at creation, and the human can decline.

**The create flow's confirmation proposes the file write and the user-project `.gitignore` line `.squad/partner.md` as one write set.** Accepting the default (both) produces the private-by-default outcome. Declining the ignore-line half while keeping the file is an explicit, informed opt-in to committing a model of the human — never something that happens by omission.

Say it exactly this way, every time it comes up: *"the plugin never commits it for you, and proposes the ignore line at creation."* **Never say "it is private"** — that overstates what a proposed-and-declinable `.gitignore` line actually guarantees, and this file is exactly the kind of artifact where that overstatement matters.

## Verbs

### create

1. Check `.squad/partner.md` doesn't already exist. If it does, route to **update**.
2. **Draft first, from what the human has *said*.** Look back over this conversation for their own statements — things they said to always ask about, things they said not to bother them with, constraints they stated, assumptions they flagged as worth checking. Draft the three sections from those statements alone.

   **What you may draft from, and what you may not.** A sentence in this draft must trace to a statement the human made in words, in this conversation. It must **not** be drawn from anything you observed: not how they've been working, not what they approved or rejected earlier, not a pattern across turns, not a preference you concluded from their tone or their pace, not anything carried over from a previous session or another project's files. Those are inferences about a person, and inferring them is precisely what makes a partner model a dossier (hard rule #12). If you catch yourself writing a line and cannot point at the sentence they said it in, cut the line — do not soften it into a question, and do not keep it "for them to correct." A draft with two real lines beats a draft with six, two of which you invented for them to disown.
3. Show the draft in full and ask **at most 3 skippable questions** to fill real gaps — never an interrogation, never a fourth question, and each one individually skippable with "skip" or "n/a." Good candidates, only if the draft left them genuinely empty: "Anything you'd rather decide for yourself unless I ask?", "Anything I should always check with you before doing?", "Any standing rule that applies to every squad here, not just this one?" Do not ask about Expertise or an attention budget — those sections don't exist.
4. Fold in the answers. The draft does the work; the human corrects it, not fills it from a blank form.
5. **The single confirmation — the exact text and the write set together.** Run the no-third-parties / no-secrets check above over the body first, and settle anything it flags before you print. Then print the **final file body verbatim**, exactly as it will land on disk, then propose both halves of the write as one accept/decline: *"That's the whole file. I'll write it to `.squad/partner.md`, and add `.squad/partner.md` to this project's `.gitignore` so it's never committed by default — the plugin never commits it for you, and proposes the ignore line at creation. Say go for both, tell me what to change, or say file-only to write it without the ignore line."* **Wait for the answer, and write nothing before it.** This confirmation is what hard rule #12 means by "confirmed in the same turn it was written" — the human is affirming *these sentences*, not merely the idea of a file, and their `go` is the confirmation for every line printed above it. If they correct a line, reprint the corrected body and ask again; a correction is never folded in silently. **Any line the human strikes, questions, or does not affirm is cut before the write** — not carried into the file for a later `update` to catch.
6. Write `.squad/partner.md` with `created` and `updated` both set to now (ISO-8601, UTC) — byte-for-byte the body they just affirmed, with nothing added between the confirmation and the write. If the human accepted the ignore line, append `.squad/partner.md` to the project's `.gitignore` (create it if absent; don't duplicate the line if it's already there).
7. Confirm: *"Partner model created."* — plus one line noting whether the ignore line was added.

### show

1. Read `.squad/partner.md`.
2. If absent: print *"No partner model yet. Run squad-partner when you want to set one up."* and stop — do not offer to draft one from context here; that only happens inside **create**, in the same turn as the human's own confirmation.
3. If present: print the full contents, then one summary line — `created` / `updated` dates, and a friendly staleness note if `updated` is more than 30 days old (a note, never a nag: state the date, don't push).

### update

1. Read the current file. If absent, route to **create**.
2. Ask what changed, or take it from what the human just said this turn.
3. **Diff first.** Show exactly what would change — added lines, removed lines, or a line reworded — against the section it lands in. Never a silent rewrite of a whole section for one new sentence. Run the no-third-parties / no-secrets check above over every **added or reworded** line before you show the diff; a line that fails it is rewritten or dropped here, not carried into the file.
4. Get an explicit confirm on the diff before writing.
5. Write the change, bump `updated` to now, leave `created` untouched.
6. Confirm: *"Partner model updated — `<section>` changed."*

### delete

1. Confirm the file exists; if not, say so and stop.
2. State what will be lost — the section headers and a one-line summary of what's under each, so the human isn't confirming blind.
3. Ask the human to type **exactly** `yes, delete`. Any other reply (including a plain "yes") does not delete — restate the requirement and wait again.
4. On the exact phrase: delete `.squad/partner.md`. Leave the `.gitignore` line in place — removing it is a separate, unasked-for edit to a file this skill doesn't own outside that one line, and a stray ignore line does no harm.
5. Confirm: *"Partner model deleted."*

## What this skill does not do

- Does not observe, infer, or accumulate anything about the human on its own initiative — every write traces to something the human said in the same turn (hard rule #12).
- Does not run automatically. `squad-onboard` offers **create** once, skippably, during onboarding; nothing else invokes this skill without the human asking.
- Does not decide what's private. It proposes the `.gitignore` line once, at creation, and never re-proposes or enforces it afterward — that choice is the human's, every time.
- Does not get re-read into a running role's context. `squad-spawn` bakes its contents into spawn prompts at dispatch time (hard rule #4 — the only reliable channel into a worktree, where the gitignored file is typically absent); this skill has no reader role of its own.
- Does not get parked or switched with a squad. `squad-goal`'s park/switch moves squad-scoped state; `partner.md` describes the human, not the initiative, and survives every park/switch untouched.
- Carries no CI lint. A lint enforcing the shape of a file no machine parses would guard nothing — unlike the roster lint, which guards a hook.

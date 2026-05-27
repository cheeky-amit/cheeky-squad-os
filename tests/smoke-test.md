# Smoke test — cheeky-squad-os end-to-end

Copy-pasteable manual verification. Exercises every skill and every hook with a small real goal. Should complete in under 10 minutes on a fresh project.

If this passes, the plugin is shipping-ready.

---

## Prerequisites

```
claude --version   # need v2.1.139 or later (for /goal in Phase 7; the rest works on v2.1.32+)
which jq           # need jq installed (brew install jq / apt-get install jq)
git --version      # any modern git
```

Create a scratch directory and cd into it:

```
mkdir -p ~/tmp/squad-smoke && cd ~/tmp/squad-smoke
git init -q
echo "# Smoke test project" > README.md
git add . && git commit -q -m "init"
```

---

## Step 1 — Install the plugin

From the directory containing this repo's checkout:

```
/plugin marketplace add /absolute/path/to/cheeky-squad-os
/plugin install cheeky-squad-os@cheeky-squad-os
```

**Verify:**

```
/plugin list
```

Should show `cheeky-squad-os@cheeky-squad-os` as installed. The plugin's three hooks should be wired (you can confirm with `/hooks`).

---

## Step 2 — SessionStart hook fires (no goal yet)

Open a fresh Claude Code session in `~/tmp/squad-smoke` and ask:

```
What's our squad goal?
```

**Expected:** Claude responds with something like *"No squad goal set — run /cheeky-squad-os:squad-onboard."* This text comes from the `SessionStart` hook injecting `additionalContext`. If Claude says *"I don't know"* or *"there is no squad"*, the hook didn't fire — check `/hooks` and the plugin install.

**Why this verifies:** the hook ran at session start, read `.squad/goal.md` (which didn't exist), and injected the static fallback notice. Claude reproduced it back to you.

---

## Step 3 — squad-onboard with a real goal

In the same session:

```
/cheeky-squad-os:squad-onboard
```

Follow the interactive flow. Use this rough input when asked *"Do you have a goal?"*:

```
audit the README in this project for clarity and rewrite weak sections — within an hour
```

`squad-onboard` should:
- Reformulate as outcome — e.g., *"Deliver a clarity-audited and rewritten README.md with at least 3 specific improvements applied, within one hour."*
- Ask you to confirm. Say yes.
- Infer mode = **One-time** (bounded deliverable, single deadline).
- Propose 2 workstreams: audit the README → rewrite the weak sections.
- Propose 2 roles. Names that fit: `readme-auditor` and `readme-rewriter`.
- Hand off to `squad-role` for generation.

**Verify the goal saved:**

```
cat .squad/goal.md
```

Should contain `mode: one-time`, an ISO-8601 `created`, an ISO-8601 `target` (about an hour from now), the outcome paragraph, and a Definition of done.

---

## Step 4 — squad-role generates two roles

When `squad-role` runs for role 1 (`readme-auditor`), answer roughly:

- **Q1 purpose:** "Read README.md, identify unclear sentences, weak headings, and missing context; write findings to reports/readme/audit.md."
- **Q2 name:** `readme-auditor`
- **Q3 file_scope:** `README.md, reports/readme/**`
- **Q4 tools:** `Read, Write, Grep`
- **Q5 model:** `sonnet`
- **Q6 isolation:** no (the two roles don't write to overlapping paths)

For role 2 (`readme-rewriter`):

- **Q1 purpose:** "Read the auditor's findings and the original README.md; rewrite weak sections inline; write the final README to reports/readme/README.rewritten.md."
- **Q2 name:** `readme-rewriter`
- **Q3 file_scope:** `reports/readme/**`
- **Q4 tools:** `Read, Write, Edit`
- **Q5 model:** `sonnet`
- **Q6 isolation:** no

**Verify generated artifacts:**

```
ls -la .claude/agents/
ls -la .squad/
cat .squad/roster.json
```

Should show:
- `.claude/agents/readme-auditor.md` and `.claude/agents/readme-rewriter.md` (both with valid YAML frontmatter — verify with `head -10`)
- `.squad/role-goal-readme-auditor.md` and `.squad/role-goal-readme-rewriter.md`
- `.squad/roster.json` with both roles, `active: true`
- `.squad/roster.md` (auto-generated human view)

---

## Step 5 — squad-spawn dispatches the squad

In the same session:

```
/cheeky-squad-os:squad-spawn
```

`squad-spawn` should:
- Read `.squad/goal.md`, see `mode: one-time`.
- Read `.squad/roster.json`, find both roles.
- Dispatch `readme-auditor` via the Agent tool first. The spawn prompt **must** contain the full text of `.squad/goal.md` and `.squad/role-goal-readme-auditor.md` — this is hard rule #4. The SessionStart hook does not fire for subagents, so prompt-baking is the only context channel.
- After `readme-auditor` finishes (writes `reports/readme/audit.md`), dispatch `readme-rewriter` with the same prompt-baking pattern.

---

## Step 6 — Verify the goal reached the subagent (the critical check)

```
ls -la reports/readme/
cat reports/readme/audit.md
```

The audit file should exist and the content should reference the **squad goal text** — phrases like "as required by the squad goal", "the goal calls for at least 3 specific improvements", or some other evidence that the subagent saw the goal. If the audit reads like a generic README review with no awareness of the goal, **the prompt-baking failed** — this is a regression.

Then:

```
cat reports/readme/README.rewritten.md
```

The rewritten README should exist, address the auditor's specific findings, and be at least as long as the original.

---

## Step 7 — Verify the PermissionRequest hook auto-approved in scope

Inspect the session transcript. During Step 5, when `readme-auditor` wrote to `reports/readme/audit.md`, there should have been **no user permission prompt** — the `PermissionRequest` hook auto-approved because `reports/readme/**` is in the role's `file_scope`. Same for `readme-rewriter` writing to `reports/readme/README.rewritten.md`.

If you saw prompts during those writes, the hook isn't matching scopes correctly — check `hooks/permission-request.sh` output by piping synthetic input through it manually:

```
echo '{"agent_type":"readme-auditor","tool_name":"Write","tool_input":{"file_path":"'$(pwd)'/reports/readme/audit.md"}}' \
  | /path/to/cheeky-squad-os/hooks/permission-request.sh
```

Should print a JSON allow decision. If it prints nothing, the hook is silently deferring — probably a glob-matching bug or roster lookup failure.

---

## Step 8 — Verify SessionStart fires with a goal present

Open a **fresh** Claude Code session in `~/tmp/squad-smoke`:

```
exit   # leave the current session
claude # start a new one in the same directory
```

Then ask:

```
What's our squad goal?
```

**Expected:** Claude responds with the full contents of `.squad/goal.md` — outcome paragraph, Definition of done, Out of scope. The user didn't tell Claude this. The `SessionStart` hook injected `.squad/goal.md` as `additionalContext` automatically.

If Claude says *"there is no goal"* or refers you to a file, the hook isn't injecting properly.

---

## Pass criteria

All of these must be true:

- [ ] Step 2: Claude reproduced the "no goal set" notice without you mentioning the file
- [ ] Step 3: `.squad/goal.md` exists with valid frontmatter
- [ ] Step 4: `.claude/agents/*.md` and `.squad/roster.json` populated correctly
- [ ] Step 5: `squad-spawn` ran without errors
- [ ] Step 6: `reports/readme/audit.md` references the squad goal text (proof of prompt-baking)
- [ ] Step 7: No permission prompts for in-scope writes
- [ ] Step 8: A fresh session knows the goal without being told (proof of SessionStart hook injecting)

If all 7 pass, the plugin is shipping-ready end-to-end.

---

## Cleanup

```
rm -rf ~/tmp/squad-smoke
/plugin uninstall cheeky-squad-os@cheeky-squad-os   # optional; leaves plugin available
```

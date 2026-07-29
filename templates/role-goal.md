---
parent: .squad/goal.md
role: <role-name>
created: <ISO-8601>
---

# Role goal — <role-name>

<!--
  This role's contribution to the squad goal — DERIVED from .squad/goal.md.
  One paragraph, outcome-framed, scoped to what THIS role owes the squad.

  The squad goal is the binding constraint. This role goal is your slice.
  If they ever conflict, the squad goal wins — surface the friction to
  the user, don't try to resolve it silently.

  Pattern (mirrors the squad goal but narrows to this role):
    <verb> <role-specific deliverable> that <serves the squad goal>
    by <intermediate deadline OR squad deadline>

  Example (role: klaviyo-data-puller, squad goal: ranked Klaviyo fix list):
    "Extract the last 90 days of Klaviyo flow performance, list health, and
     deliverability metrics into structured JSON under reports/klaviyo/,
     within 48 hours, so downstream roles can rank and write the report."
-->

<role's outcome paragraph>

## Owned outputs

<!--
  The specific artifacts this role produces. Each lives inside the role's
  file_scope (registered in .squad/roster.json). Give paths or path patterns.

  These ARE the role's hand-off surface — other roles consume them by
  reading from disk. Don't write large artifacts into chat replies.
-->

- <artifact 1 with path>
- <artifact 2 with path>

## Hand-offs

<!--
  Which role(s) consume this role's outputs. Be explicit. If this is the
  last role in the chain, write "user" or "none".

  This creates an implicit dependency graph across the squad. squad-spawn
  uses it to order sequential dispatches when parallel execution isn't
  possible.
-->

- <next role>: <what they need from you>

## Stop conditions

<!--
  Hard rule #14 — declared bounds. 2-4 bullets, derived by squad-role from
  this role's purpose, its tools, and the squad goal's Out of scope. Every
  bullet has exactly one of two verbs:

    needs: <precondition> — checked at spawn preflight (squad-spawn's
           dispatch triage probes what it can) and again by the role
           itself at the start of its run, before committing to the
           approach in its engagement record.
    stop:  <mid-run bound> — the role self-polices this while working;
           there is no external monitor. Hitting it ends the run: the
           role writes .squad/role-plan-<role>.md with status: escalated
           and fired: set to this bullet verbatim (see templates/role-
           plan.md), then stops. That file is the only hand-back.

  A condition that cannot be checked is not a condition. Contrast:
    needs: the Klaviyo MCP connector responds to a read      <- checkable:
           call it, get pass or fail
    needs: the data looks reasonable                         <- not a
           condition: nothing to run, nothing that fails
    stop:  any API returns 403 twice                         <- checkable:
           count it, compare to two
    stop:  if things get complicated                         <- a mood,
           not a bound

  These ride the already-prompt-baked role goal (hard rule #4) — the full
  text of this file is injected into every spawn prompt, so a role reads
  its own stop conditions without any new channel. Do not invent a second
  place to declare them.

  Escalation is evidence generation, never decision (hard rule #10): a
  fired stop condition blocks a `met` verdict until the human rules on it
  in .squad/verification.md. No bullet here, and nothing this role
  writes, can clear that block itself.
-->

- `needs:` <precondition>
- `stop:` <mid-run bound>

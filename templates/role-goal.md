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

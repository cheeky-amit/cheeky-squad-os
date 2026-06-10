---
# Hand-off manifest template — the structured worker↔worker communication channel
#
# A role writes one of these when a deliverable is ready for a downstream role.
# Path convention (enforced by file_scope — squad-role registers each role's
# outbox glob `.squad/role-comm-<name>--*` automatically):
#
#   .squad/role-comm-<from>--<to>.md
#
# e.g. .squad/role-comm-readme-auditor--readme-rewriter.md
#
# Who reads it:
#   - squad-spawn bakes every ready manifest addressed to a role into that
#     role's spawn prompt (One-time mode — prompt-baking is the only reliable
#     parent→worker channel, hard rule #4; manifests ride the same channel).
#   - A running teammate (Multi-use mode) reads its inbox directly:
#     .squad/role-comm-*--<own-name>.md. Agent Teams messaging stays the live
#     channel; the manifest is the durable record of WHAT was handed off.
#
# Lifecycle: ephemeral, per-ENGAGEMENT, gitignored (.squad/role-comm-* in
# .gitignore). The dispatcher (squad-spawn / squad-workflow) deletes leftover
# manifests at the start of each fresh run — except when the run is an explicit
# follow-on stage (squad-workflow --chain, or a planned next stage), where the
# previous stage's manifests are the input. Within a run: overwrite your own
# previous manifest to the same consumer; set status: superseded instead of
# deleting if the consumer may already have read it. Consumers can judge
# freshness from `created`.
#
# Placeholders:
#   {{from}}     — producer role name (must equal the filename's <from>)
#   {{to}}       — consumer role name, or "any" for broadcast
#   {{created}}  — ISO-8601 timestamp
#   {{status}}   — ready | superseded
from: {{from}}
to: {{to}}
created: {{created}}
status: {{status}}
---

# Hand-off: {{from}} → {{to}}

## What's ready

<!-- One bullet per artifact: path (inside the producer's file_scope) + one-line description. -->

- `<path/to/artifact>` — <what it is, one line>

## How to consume

<!-- Concrete instructions: read order, entry point, schema or format notes.
     Write for the consumer role — it has no other context about your work. -->

## Caveats

<!-- Known gaps, partial data, low-confidence sections, anything the consumer
     must not assume is complete. An empty caveats section means "consume
     without reservation" — only leave it empty if that is true. -->

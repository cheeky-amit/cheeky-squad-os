# full-funnel-agency — the artifacts

The real files behind [`../full-funnel-agency.md`](../full-funnel-agency.md), the worked
example of a five-seat marketing agency squad for a direct-to-consumer brand.

## What this demonstrates

- **The 5-seat cap (hard rule #16).** An honest decomposition produced eight workstreams.
  The roster has five roles, because three merges each removed a hand-off rather than
  dropping work.
- **Skill onboarding, both dimensions (`squad-role` Q8).** Fourteen skills — **eleven
  knowledge** (how a role thinks) and **three execution** (how a role acts on a live
  platform) — every one researched from an existing source and attributed, nothing
  authored from scratch. Approval came from `skill_onboarding: auto` in the goal
  frontmatter, so every entry carries `approval_mode: "auto"` and an `approved_at`
  timestamp.
- **A declared capability gap.** `performance-media-buyer` operates Meta Ads but has no
  connected MCP server for it. Rather than write a skill for writes it cannot perform, it
  declared the gap in its role goal and routed the proposed fix through `squad-env`'s
  `global_needs`. See `role-goal-performance-media-buyer.md`.
- **The provenance contract.** Every skill file ends with `## Provenance & limits` —
  sources searched including the empty ones, intake date, known limits, and the standing
  line that this is the best found at intake, not the best that exists. `squad-roster`'s
  Add operation refuses to register an entry whose file lacks that block.
- **Roster v2 with `onboarded_skills`.** Five roles, one sandbox `environment`, Claude
  provider overrides, and fourteen onboarded-skill entries with explicit `kind` values —
  validating against the plugin's own contract loader.

## Map

```
full-funnel-agency/
├── README.md                                  this file
├── roster.json                                schema_version 2 — 5 roles, 14 onboarded skills
├── role-goal-performance-media-buyer.md       the role goal carrying the declared Meta gap
└── skills/
    ├── studio-producer/
    │   ├── weekly-client-brief/SKILL.md            (knowledge)
    │   └── program-risk-register/SKILL.md          (knowledge)
    ├── performance-media-buyer/
    │   ├── paid-media-audit/SKILL.md               (knowledge)
    │   ├── budget-pacing-review/SKILL.md           (knowledge)
    │   └── google-ads-operations/SKILL.md          (execution)
    ├── creative-strategist/
    │   ├── hook-matrix/SKILL.md                    (knowledge)
    │   ├── creative-brief/SKILL.md                 (knowledge)
    │   └── organic-social-plan/SKILL.md            (knowledge)
    ├── tracking-analyst/
    │   ├── conversion-tracking-audit/SKILL.md      (knowledge)
    │   ├── attribution-reconciliation/SKILL.md     (knowledge)
    │   └── ga4-event-audit-operations/SKILL.md     (execution)
    └── lifecycle-organic-marketer/
        ├── lifecycle-sequence-spec/SKILL.md        (knowledge)
        ├── organic-search-brief/SKILL.md           (knowledge)
        └── klaviyo-flow-operations/SKILL.md        (execution)
```

`skills/` mirrors the layout a live squad has on disk. In a real project these files sit
at `.squad/skills/<role-id>/<skill-name>/SKILL.md`, which is exactly what each roster
entry's `local_path` says — `squad-spawn` resolves those to absolute paths before baking
them into a role's spawn prompt.

Execution coverage by seat: `studio-producer` and `creative-strategist` operate no
platform, so the execution dimension was skipped and said so. `tracking-analyst` and
`lifecycle-organic-marketer` operate platforms they can reach. `performance-media-buyer`
operates two, has an execution skill for one, and a declared gap for the other.

## Validate the roster

Run from the repository root:

```bash
python3 -c "import json,sys; sys.path.insert(0,'src'); from cheeky_squad_portability.contracts import Roster; Roster.from_dict(json.load(open('examples/full-funnel-agency/roster.json'))); print('roster valid')"
```

Expected output:

```
roster valid
```

## Sources

Every skill carries a `Source:` line in its body and a full `Sources searched` line in its
`## Provenance & limits` block, including the searches that came back empty.

**Knowledge skills** — all adapt files from
[`msitarzewski/agency-agents`](https://github.com/msitarzewski/agency-agents) (MIT):

| Skill | Source file |
|---|---|
| `weekly-client-brief`, `program-risk-register` | `project-management/project-management-studio-producer.md` |
| `paid-media-audit` | `paid-media/paid-media-auditor.md` |
| `budget-pacing-review` | `paid-media/paid-media-ppc-strategist.md` (+ `paid-media-paid-social-strategist.md`) |
| `hook-matrix` | `paid-media/paid-media-creative-strategist.md` |
| `creative-brief` | `marketing/marketing-content-creator.md` |
| `organic-social-plan` | `marketing/marketing-instagram-curator.md` |
| `conversion-tracking-audit` | `paid-media/paid-media-tracking-specialist.md` |
| `attribution-reconciliation` | `paid-media/paid-media-auditor.md` |
| `lifecycle-sequence-spec` | `marketing/marketing-email-strategist.md` |
| `organic-search-brief` | `marketing/marketing-seo-specialist.md` |

Two pairs share a source file on purpose. `paid-media-auditor.md` was split by reader —
its structural checkpoints went to `performance-media-buyer`, its measurement and
change-history checkpoints to `tracking-analyst` — and that split is what let five seats
absorb an eight-workstream decomposition. The studio-producer's two skills come from one
file that bundles two different jobs.

**Execution skills** — all distilled from official platform documentation:

| Skill | Sources |
|---|---|
| `google-ads-operations` | [Google Ads API](https://developers.google.com/google-ads/api/docs/start), [reporting overview](https://developers.google.com/google-ads/api/docs/reporting/overview), [Ads Scripts](https://developers.google.com/google-ads/scripts/docs/start) |
| `ga4-event-audit-operations` | [GA4 collection](https://developers.google.com/analytics/devguides/collection/ga4), [DebugView](https://support.google.com/analytics/answer/7201382), [Measurement Protocol](https://developers.google.com/analytics/devguides/collection/protocol/ga4), [Meta Conversions API](https://developers.facebook.com/docs/marketing-api/conversions-api) |
| `klaviyo-flow-operations` | [Klaviyo API overview](https://developers.klaviyo.com/en/reference/api_overview), [flows reference](https://developers.klaviyo.com/en/reference/get_flows) |

None of the three reproduces an endpoint signature, field name, or API version — those
change per release, and a stale signature in a skill file is worse than no signature. Each
says so in its own `Known limits`.

## Refreshing this squad

These fourteen skills are what research found on their intake date, not what is best. The
way that gets corrected is `squad-roster`'s **Refresh skills** operation, which re-runs the
two-dimension research against the existing set and proposes upgrades through the same
approval gate Q8 used. The declared Meta gap is the obvious first candidate: connect a Meta
Marketing API MCP server and Refresh can close it.

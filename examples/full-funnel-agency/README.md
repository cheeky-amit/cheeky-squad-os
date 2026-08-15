# full-funnel-agency — the artifacts

The real files behind [`../full-funnel-agency.md`](../full-funnel-agency.md), the worked
example of a five-seat marketing agency squad for a direct-to-consumer brand.

## What this demonstrates

- **The 5-seat cap (hard rule #16).** An honest decomposition produced eight workstreams.
  The roster has five roles, because three merges each removed a hand-off rather than
  dropping work.
- **Skill onboarding (`squad-role` Q8).** Eleven skills, every one researched from an
  existing open-source source file, adapted, and attributed — nothing authored from
  scratch. Approval came from `skill_onboarding: auto` in the goal frontmatter, so every
  entry carries `approval_mode: "auto"` and an `approved_at` timestamp.
- **Roster v2 with `onboarded_skills`.** Five roles, one sandbox `environment`, Claude
  provider overrides, and eleven onboarded-skill entries — validating against the
  plugin's own contract loader.

## Map

```
full-funnel-agency/
├── README.md                         this file
├── roster.json                       schema_version 2 — 5 roles, 11 onboarded skills
└── skills/
    ├── studio-producer/
    │   ├── weekly-client-brief/SKILL.md
    │   └── program-risk-register/SKILL.md
    ├── performance-media-buyer/
    │   ├── paid-media-audit/SKILL.md
    │   └── budget-pacing-review/SKILL.md
    ├── creative-strategist/
    │   ├── hook-matrix/SKILL.md
    │   ├── creative-brief/SKILL.md
    │   └── organic-social-plan/SKILL.md
    ├── tracking-analyst/
    │   ├── conversion-tracking-audit/SKILL.md
    │   └── attribution-reconciliation/SKILL.md
    └── lifecycle-organic-marketer/
        ├── lifecycle-sequence-spec/SKILL.md
        └── organic-search-brief/SKILL.md
```

`skills/` mirrors the layout a live squad has on disk. In a real project these files sit
at `.squad/skills/<role-id>/<skill-name>/SKILL.md`, which is exactly what each roster
entry's `local_path` says — `squad-spawn` resolves those to absolute paths before baking
them into a role's spawn prompt.

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

Every skill carries a `Source:` line in its body. All eleven adapt files from
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

# Changelog

All notable changes to cheeky-squad-os are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [0.2.0] - 2026-06-10

The supervision release. The tagline always promised "roles, responsibilities, communication, and supervision" — this version ships the supervision component.

### Added

- **`squad-verify` skill** — the seventh skill, closing the loop after dispatch. Checks every bullet of the goal's `## Definition of done` against the squad's actual deliverables, marks each signal PASS / FAIL / NEEDS-HUMAN (evidence or NEEDS-HUMAN — never a guess), and writes `.squad/verification.md` with a met / partial / unmet verdict. Read-only judging: it never modifies `goal.md` or `roster.json`.
- **`skills/squad-verify/scripts/verify.sh`** — jq-based evidence scaffold emitting JSON lines: one per Definition-of-done signal, one per active role (deliverable counts under `file_scope`, role-goal presence), plus a summary line. Skips YAML frontmatter and HTML comments when parsing the goal.
- **`templates/verification.md`** — the report skeleton (per-signal sections, role-deliverables table, verdict frontmatter).
- **Hard rule #10** — "Synthesis summarizes, verification decides": `.squad/verification.md` is the only authority for declaring the goal met. `squad-spawn`'s per-spawn synthesis and `/squad-workflow`'s digest now end by handing off to `squad-verify`.
- **`tests/verify.bats`** — 14 automated cases covering preflight refusals, Definition-of-done parsing (frontmatter/HTML-comment exclusion), glob scope counting, inactive-role skipping, and JSON-lines validity.
- **CI example-roster schema lint** — every fenced roster JSON block in `examples/*.md` is validated against the canonical `roster.json` schema. Invented keys (`allowed_paths`, `depends_on`, `schema_version`, …) silently disable the permission hook, so they now fail the build.
- **`docs/workflows-runtime-reference.md`** — verified runtime reference for the dynamic-Workflow DSL behind `templates/squad-dispatch.workflow.js`.

### Fixed

- **Permission hook mid-path glob over-approval** — a `file_scope` glob like `data/*` previously matched `data/sub/secret` because bash `[[ == ]]` lets `*` cross `/`. The matcher now requires segment-for-segment matching (`*` never crosses `/`); `prefix/**` remains the way to grant a subtree.
- **Example rosters rewritten to the canonical schema** — all three walkthroughs (`klaviyo-audit`, `landing-page-redesign`, `weekly-competitive-intel`) previously showed invented roster keys and role-frontmatter fields that the hook and spawn path never read. They now match `templates/roster.json` and the subagent frontmatter spec exactly.
- **Docs truth sync** — README's hooks story now matches the shipped hook (in-sandbox scaffolding Bash auto-approves; it is no longer claimed that "Bash always defers"); component counts corrected to 7 skills / 6 templates; `squad-roster` no longer claims the PermissionRequest hook calls it (the hook reads `roster.json` directly); stale "Phase 7" / original-brief references removed; roster schema docs now include the `environment` block.
- **`tests/permission-request.bats`** — allow assertions are now structural (`jq -e '.hookSpecificOutput.decision.behavior == "allow"'`) instead of substring matches; 4 new mid-path glob cases.

## [0.1.0] - 2026-06-08

Initial release: 6 skills (`squad-onboard`, `squad-goal`, `squad-role`, `squad-env`, `squad-spawn`, `squad-roster`), 3 hooks (SessionStart goal injection, UserPromptSubmit goal tagging, PermissionRequest scoped auto-approval), 3 modes (One-time / Multi-use / Evergreen), role environments with sandbox-scoped provisioning, optional dynamic-Workflow dispatch, zero shipped role files.

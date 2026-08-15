# Roadmap

The north star is a trustworthy squad lifecycle that can move between supported agent
runtimes without losing its role intent or inventing parity the runtimes do not have.
Releases are judged by working mechanisms, explicit unsupported areas, and reproducible
evidence.

## Shipped foundations

| Pillar | Status | Evidence |
| --- | --- | --- |
| Bespoke role authoring | Shipped | Goal-derived roles; zero default role files |
| Goal and role supervision | Shipped | Goal, role goals, engagement records, belief ledger, verification artifact |
| Claude lifecycle runtime | Shipped | Three hooks, nine skills, cadence-specific dispatch |
| Provider-neutral contract | Shipped in 1.1.0 | Manifest/roster schema v2, frozen dataclasses, pure legacy migration |
| Claude and Codex compilation | Shipped in 1.1.0 | Provider goldens for read-only and mutating roles |
| Scoped export | Shipped in 1.1.0 | Session/project/user/plugin plan-confirm-apply flow |
| Safe lifecycle | Shipped in 1.1.0 | Hash-bound plans, receipts, rollback, validation, conservative uninstall |
| Standalone portability | Shipped in 1.1.0 | Fresh-home packages work without the generator installed |
| Honest provider governance | Shipped in 1.1.0 | Capability matrix labels mechanical, sandbox, instructional, unsupported |

## Next priorities

1. **Executable verification evidence.** Let Definition-of-done signals declare
   read-only evidence commands and record exact output/exit status.
2. **Goal-drift enforcement option.** Add an opt-in amendment gate beyond the current
   observational prompt tag.
3. **Evergreen scheduling integration.** Replace printed external scheduler guidance
   when supported provider APIs expose a stable plugin-accessible surface.
4. **Mode escalation.** Guide `one-time` to `multi-use` or `evergreen` without losing
   canonical roles and receipts.
5. **Provider capability evolution.** Add mechanical Codex file ownership only if Codex
   exposes an official, testable per-role blocking mechanism. Until then ownership stays
   instructional and mutating roles stay sequential.
6. **Windows support.** Replace or isolate Bash-dependent shared runtime pieces before
   claiming Windows compatibility.
7. **Remote roster transport.** Consider explicit encrypted/signed transport after local
   receipts, collision policy, and private-state exclusions remain the default.
8. **Public marketplace presence.** Separate product decision. Generation and release
   tooling must never submit automatically.
9. **Vendor onboarded-skill payloads.** Export packages currently carry only the
   `onboarded_skills` manifest entries (name, source, local path, purpose, approval
   record) as part of the portable roster contract. The skill files themselves, under
   `.squad/skills/**`, are not copied into the snapshot — an exported squad's
   onboarded-skill references point at paths the export doesn't carry. Vendor the
   payload bytes alongside the manifest so an exported squad is truly self-contained.

## Non-goals

- A universal role catalog. The goal continues to generate the team.
- Silent global installation or auto-enablement.
- Treating `project` output as a plugin package.
- Ongoing generated-package dependency on this repository.
- Claiming identical enforcement across Claude and Codex.
- Exporting partner models, secrets, workspaces, or live engagement state by default.

## Release evidence

Every release keeps Ubuntu and macOS CI green and runs:

- `ruff check` and `ruff format --check`;
- complete `pytest` and `bats` suites;
- `shellcheck`, Mermaid lint, and JavaScript syntax checks;
- JSON Schema/TOML/manifest parsing and provider golden diffs;
- path-boundary, receipt, rollback, idempotency, uninstall-preservation, and fresh-home
  package tests;
- version consistency and secret scanning;
- real Claude and Codex smoke tests appropriate to each provider surface.

Synthesis summarizes; verification decides. That standard applies to the product too.

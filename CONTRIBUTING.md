# Contributing to cheeky-squad-os

Contributions must preserve one shared squad contract while keeping provider syntax,
discovery, permissions, and activation honest.

## Repository layout

```text
schemas/                         manifest, roster, role, and export-plan JSON Schemas
src/cheeky_squad_portability/   frozen contracts, migration, plans, receipts, exporter
src/.../adapters/               pure Claude and Codex byte compilers
.claude-plugin/                 source Claude lifecycle plugin manifest
.codex-plugin/                  source Codex plugin manifest
skills/                         nine lifecycle/authoring skills
hooks/                          Claude SessionStart, UserPromptSubmit, PermissionRequest
templates/                      lifecycle and dispatch templates
examples/                       cadence examples and portable export walkthrough
tests/python/                   contracts, adapters, exporter, receipts, hardening
tests/*.bats                    Bash runtime tests
tests/fixtures/                 canonical contracts and provider goldens
docs/                           ADRs, provider guides, compatibility/security
```

## Architecture rules

### Shared contract, provider-owned syntax

Provider-neutral dataclasses and schemas own purpose, description, ownership,
capabilities, reasoning, environment, and overrides. Claude and Codex adapters own their
own file formats and mappings. Do not put `.claude`, `.codex`, TOML, or plugin layout
decisions in the neutral contract.

Adapters are pure: they validate inputs and return a deterministic path-to-bytes map.
They do not choose a destination or write to disk.

### Cadence is not destination

`one-time`, `multi-use`, and `evergreen` control execution. `session`, `project`, `user`,
and `plugin` control discovery/write scope. A new destination is not a new mode. A new
mode must justify a genuinely different cadence and dispatch primitive.

### Export is a lifecycle verb

The human authors goals and roles through the existing skills. Export belongs to
`squad-roster`, which owns the canonical role collection. Do not add another
provider-specific role-authoring skill.

### Vendored snapshots

Generated output must work without importing this repository. Plugin generation and
plugin installation are separate actions. No command may auto-enable, auto-install,
publish, or submit an exported package.

## Python standards

- Python 3.11+ and PEP 8.
- Type annotations for public and internal functions.
- Frozen dataclasses for contracts and value objects.
- Prefer immutable tuples/mappings and deterministic sorting.
- Validate at boundaries and raise a specific contract/export error.
- Do not mix filesystem I/O into compilers.
- Use standard-library TOML parsing in tests; do not hand-wave generated syntax.
- Format/lint with `ruff`; test with `pytest`.

When a contract changes, update its Python parser/serializer, JSON Schema, canonical
fixtures, round-trip tests, adapter goldens, and docs in the same change.

## Export safety rules

A plan must enumerate the complete write/delete/executable set and hash all generated
bytes. Apply only an exact, freshly recomputed matching plan. Preserve these invariants:

- session produces no discovery/global writes;
- project writes only inside an explicit selected Git repository;
- user writes only to an explicit matching home after a second confirmation;
- plugin writes only to an explicit non-root, non-home selected directory;
- root targets, traversal, symlink components/escapes, ambiguous paths, and unowned
  collisions fail closed;
- re-export/uninstall operates only on receipt-owned files whose hashes still match;
- interrupted apply restores prior owned files;
- `.squad/partner.md`, `.env*`, workspaces, engagement/hand-off records, credentials,
  and live/private state stay excluded by default.

Never broaden a failure into “best effort.” A stale plan or uncertain ownership requires
a new preview or human decision.

## Provider rules

### Claude

Generated agents are squad-namespaced Markdown. Generated plugins are self-contained and
register shared hooks only when Claude is the manifest-selected runtime owner. Exact
provider-only capabilities require explicit overrides.

Keep hook behavior fail-open: defer to normal user permission flow rather than silently
deny. Run the existing Bats allow/defer matrix for any hook-related documentation or
behavior change.

Official contracts:
[subagents](https://code.claude.com/docs/en/sub-agents) and
[plugins](https://code.claude.com/docs/en/plugins-reference).

### Codex

Project/user agents are namespaced TOML with `name`, `description`, and
`developer_instructions`. Standalone plugins carry native manifests and prompt-baked
role skills because plugin custom-agent discovery is not assumed.

Codex v1 ownership is instructional. Mutating roles dispatch sequentially. Do not add a
claim of mechanical file-scope enforcement unless a tested Codex runtime mechanism is
actually implemented. Sandbox restrictions are accurately labeled sandbox-enforced.

Official plugin contract:
[Build plugins](https://developers.openai.com/plugins/build/plugins).

## Documentation rules

- Label major behavior `mechanically enforced`, `sandbox-enforced`, `instructional`, or
  `unsupported` when the distinction affects user trust.
- Keep project and plugin output distinct; keep generation and installation distinct.
- User/global is never the default.
- Preserve legacy behavior claims only when migration tests prove them.
- Update README, architecture/logic, compatibility, provider guide, smoke test, and
  changelog alongside behavior.
- Use GitHub-flavored CommonMark and valid Mermaid syntax.

## Full local gate

Install Python development dependencies plus `bats-core` and `shellcheck`, then run:

```bash
ruff check src tests/python
ruff format --check src tests/python
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests
shellcheck hooks/*.sh skills/**/scripts/*.sh tests/*.sh
bats tests/*.bats
bash tests/mermaid-lint.sh
node --check templates/squad-dispatch.workflow.js
```

The test suite must additionally cover JSON Schema validation, TOML parsing, provider
goldens, path boundaries, version consistency, generated-package validation, and secret
scanning. CI must run supported validation on Ubuntu and macOS.

Run the real manual walkthrough in [tests/smoke-test.md](tests/smoke-test.md) before a
release. It covers Claude lifecycle/plugin behavior plus Codex project-agent,
skill-discovery, plugin, and prompt-baked dispatch in temporary homes.

## Reviews and commits

- Use conventional commits: `feat|fix|refactor|docs|test|chore|perf|ci: description`.
- Check `git status` before and after changes; preserve unrelated user work.
- Never commit `.env`, credentials, caches, generated temp homes, or `node_modules`.
- Code, security, and documentation reviews are separate release gates. A specialist
  does not approve their own work.
- Do not create a tag, GitHub release, or marketplace submission as part of a code PR
  unless the task explicitly authorizes it.

## Issues

Bug reports should include OS, Python/provider CLI versions, destination, selected
providers, redacted manifest/roster, the plan ID, and expected versus observed behavior.
Do not attach receipts or plans until checking them for private paths.

Feature proposals should lead with the user outcome and name the enforcement category.
“Provider parity” is not sufficient if the underlying runtimes expose different
mechanisms.

## License

By contributing, you agree that your contribution is licensed under the MIT License.

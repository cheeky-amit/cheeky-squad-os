# cheeky-squad-os contributor guide

## Product contract

cheeky-squad-os generates a bespoke squad from a goal, then exports an immutable,
self-contained snapshot for Claude Code, Codex, or both. Execution cadence
(`one-time`, `multi-use`, `evergreen`) and export destination (`session`, `project`,
`user`, `plugin`) are independent choices.

Version 1.1.0 has three architectural layers:

- `contracts.py`, `migration.py`, and `plan.py` own provider-neutral schemas,
  deterministic legacy migration, and content-addressed plans.
- `adapters/claude.py` and `adapters/codex.py` own provider syntax. Adapters render
  bytes and never choose a filesystem destination.
- the export engine owns target boundaries, receipts, atomic application,
  validation, and receipt-based uninstall.

The existing nine lifecycle skills remain the authoring surface. `export` is a verb
of `squad-roster`; do not add a provider-specific role-authoring skill.

## Safety invariants

- A plan must enumerate the complete write/delete set. Apply only a freshly
  recomputed plan whose ID exactly matches the user's confirmation.
- `session` writes no discovery or global files. `project` stays inside the selected
  Git repository. `user` requires a second global-write confirmation and namespaces
  every artifact. `plugin` writes only to the selected directory and never installs
  or enables the result.
- Re-export may replace or delete only receipt-owned, unmodified files. Unowned
  collisions, traversal, symlink components, roots, home-directory misuse, and
  ambiguous paths fail closed.
- Exported packages are vendored snapshots. Do not introduce a runtime dependency on
  this repository.
- Never export `.squad/partner.md`, `.env*`, workspaces, engagement records, secrets,
  or other live/private state by default.
- Codex v1 file ownership is instructional. Mutating Codex roles run sequentially.
  Do not claim a file-scope blocking hook exists.

## Development standards

- Python: Python 3.11+, type annotations, frozen dataclasses, immutable values where
  practical, `ruff` formatting/linting, and `pytest`.
- Shell: run `shellcheck` and `bats`; hooks fail open and defer permission decisions
  to the human.
- JavaScript: run `node --check` on the workflow template.
- JSON/TOML: parse generated artifacts and keep golden fixtures deterministic.
- Use conventional commits and update code, tests, and documentation together.

Before a PR, run the full gate documented in [CONTRIBUTING.md](CONTRIBUTING.md).
Preserve unrelated working-tree changes and never commit credentials or `.env` files.

## Documentation map

- [README.md](README.md): product contract and quickstart
- [ARCHITECTURE.md](ARCHITECTURE.md): system design and enforcement boundaries
- [LOGIC.md](LOGIC.md): lifecycle and data-flow diagrams
- [docs/portability.md](docs/portability.md): export contract and destinations
- [docs/compatibility-security.md](docs/compatibility-security.md): provider matrix and
  security posture
- [docs/providers/claude.md](docs/providers/claude.md) and
  [docs/providers/codex.md](docs/providers/codex.md): provider-specific activation

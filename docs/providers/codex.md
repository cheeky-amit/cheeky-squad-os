# Codex provider guide

The Codex adapter compiles active canonical roles into namespaced TOML custom agents for
project/user discovery and into prompt-baked skills for standalone plugin transport.

## Project and user agents

Each role TOML contains the required fields:

```toml
name = "<generated-provider-role-id>"
description = "Write the verified release report"
developer_instructions = "...provider-neutral purpose and boundaries..."
sandbox_mode = "workspace-write"
```

Optional model and reasoning settings are derived from the canonical reasoning profile
or an explicit Codex override. Read-only roles default to `read-only`; roles with a
mutating capability use `workspace-write`. Repo-local role skills are generated under
`.agents/skills/`.

Environment requirements may identify variable names, directories, or tool names;
generated instructions do not embed environment variable values, live context locations,
or tool install/verification commands. Canonical authored goals arrive through the
vendored context snapshot instead.

The exporter mounts project agents under `.codex/agents/`. User output uses the
corresponding namespaced user discovery surface and requires a separate global-write
confirmation.

## Standalone plugin

The generated directory has a native top-level `.codex-plugin/plugin.json` for the
dual-provider package contract. Its installable Codex surface is a matching vendored copy
under `plugins/<squad-namespace>/`, cataloged by
`.agents/plugins/marketplace.json` with the local source
`./plugins/<squad-namespace>`. It also includes packaged role prompts, role skills, a
squad dispatch skill, canonical contracts, runtime snapshot, activation instructions,
license, and receipt.

Codex plugins do not directly package custom-agent discovery for these generated roles.
The standalone dispatcher therefore prompt-bakes every packaged role. This is a stated
compatibility strategy, not an invisible substitute for custom-agent discovery.

Inspect the selected directory, then activate it deliberately with the current two-step
Codex CLI flow. Run the first command from the generated directory, then copy the
generated install command verbatim from `ACTIVATION.md`; collision-safe identifiers are
not meant to be hand-derived from the squad ID:

```bash
codex plugin marketplace add "$(pwd -P)"
# Then run the exact `codex plugin add ...` line from ACTIVATION.md.
```

The first command registers the local marketplace; the second installs the plugin selected
from that marketplace. `codex plugin add /path` is not the plugin-install syntax. Generation
runs neither command and never installs, enables, publishes, or submits the package. No
public Codex marketplace submission is part of this release. Official package reference:
[Build plugins](https://developers.openai.com/plugins/build/plugins).

For project/user role identifiers, inspect the export plan and the generated
`.squad/provider-role-map.json`; do not infer identifiers from canonical role names.

The repository's base `.codex-plugin/plugin.json` is validated as a plugin manifest, but
the source checkout is not itself advertised as a local marketplace: a marketplace source
must point to `./plugins/<plugin-name>`, not back to `./`. Generate a standalone export or
place a copied checkout at `plugins/cheeky-squad-os` in a deliberately managed personal
marketplace when testing the base plugin.

## Sequential mutation policy

The generated developer instructions and dispatch skill distinguish read-only from
mutating roles:

- dependency-safe read-only roles may run concurrently;
- every mutating role runs sequentially and never concurrently with another mutating
  squad role.

This avoids two writers racing across an instructional boundary. It is not a claim that
the role owns a mechanically locked set of files.

## Enforcement boundary

In Codex v1:

- `sandbox_mode` is sandbox-enforced by the active Codex runtime;
- provider tool policy remains sandbox/tool-policy enforced;
- `file_ownership` is instructional;
- there is no exported file-scope auto-approval hook;
- the exporter does not claim Claude’s `PermissionRequest` hook applies to Codex.

If a mutating role writes outside its instructed ownership paths, the active sandbox may
still restrict where it can write, but this release does not register a narrower
per-role file-scope mechanism. Reports and user-facing docs must preserve that distinction.

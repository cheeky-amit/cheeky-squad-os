# Compatibility and security

Version 1.1.0 treats Claude Code and Codex as first-class outputs without pretending
their runtimes have identical control surfaces.

## Enforcement labels

- **Mechanically enforced**: code rejects or blocks a violating operation. A hook that
  only limits automatic approval is described separately and does not earn this label
  for the underlying write.
- **Sandbox-enforced**: the active provider sandbox/tool policy restricts the operation.
- **Instructional**: the role or dispatcher is told the rule; there is no blocking
  mechanism proving compliance.
- **Unsupported**: this release does not provide the capability for that provider/path.

## Provider capability matrix

| Capability | Claude project/user | Claude plugin | Codex project/user | Codex plugin |
| --- | --- | --- | --- | --- |
| Namespaced role discovery | Mechanically enforced by compiler/path validation | Mechanically enforced by compiler; plugin-scoped discovery | Mechanically enforced by compiler/path validation | Unsupported directly; roles are prompt-baked into skills |
| Required role fields | Mechanically enforced; Markdown frontmatter | Mechanically enforced; Markdown frontmatter | Mechanically enforced; TOML `name`, `description`, `developer_instructions` | Mechanically enforced for native plugin manifest and skills |
| Tool/capability mapping | Mechanically validated by adapter | Mechanically validated by adapter | Instructional plus active Codex tool policy | Instructional plus active Codex tool policy |
| File ownership boundary | Instructional for the write itself; the active runtime-owner hook mechanically limits **automatic approval eligibility** | Instructional for the write itself; vendored hooks mechanically limit **automatic approval eligibility** when Claude is runtime owner | **Instructional in v1** | **Instructional in v1** |
| Workspace access | Provider permission policy; eligible writes may be auto-approved by the hook | Provider permission policy plus runtime-owner auto-approval hook | Sandbox-enforced by generated `read-only` or `workspace-write` mode | Sandbox-enforced by the invoking Codex session |
| Concurrent read-only dispatch | Supported where dependencies allow | Supported where dependencies allow | Instructional, dependency-safe concurrency allowed | Instructional, dependency-safe concurrency allowed |
| Concurrent mutating dispatch | Claude dispatch path plus hook/runtime policy | Claude dispatch path plus hook/runtime policy | Unsupported by squad policy; dispatched sequentially | Unsupported by squad policy; prompt-baked dispatcher is sequential |
| File-scope auto-approval gate | Supported only by the active Claude lifecycle runtime; out-of-scope requests defer to the human | Supported only when Claude is runtime owner; out-of-scope requests defer to the human | Unsupported | Unsupported |
| Shared lifecycle hooks | Runtime-owner only | Runtime-owner only | Unsupported as an equivalent file-scope auto-approval gate | Unsupported as an equivalent file-scope auto-approval gate |
| Standalone vendored package | Supported | Supported | Supported through plugin skills/prompts | Supported |
| Receipt-based removal | Mechanically enforced by exporter | Mechanically enforced by exporter | Mechanically enforced by exporter | Mechanically enforced by exporter |

The important negative claim is explicit: Codex v1 has no registered file-scope
auto-approval hook. `file_ownership` coordinates roles and is included in developer instructions, but
it is not a mechanical boundary. Mutating Codex roles run sequentially to avoid races;
that policy is prompt-baked and tested, not represented as a nonexistent scope hook.

## Destination boundary matrix

| Destination | Target requirement | Confirmation | Filesystem guarantee |
| --- | --- | --- | --- |
| `session` | No target accepted | Matching plan ID | Mechanically enforced empty write/delete set |
| `project` | Existing selected Git root | Matching plan ID | Mechanically constrained to that repository |
| `user` | Target exactly equals explicit absolute home | Plan ID plus separate global-write confirmation | Mechanically namespaced and receipted under that home |
| `plugin` | Existing selected non-root, non-home directory | Matching plan ID | Mechanically constrained to package directory; no installation step |

## Export safety properties

The exporter validates at boundaries and fails before mutation for:

- malformed manifests, rosters, plans, TOML, and JSON;
- missing selected providers or inconsistent execution modes;
- absolute, non-normalized, traversal, or private/live output paths;
- symlink components and escapes;
- filesystem-root, home-directory, or wrong-repository targets;
- file/directory ambiguity and duplicate output paths;
- unowned collisions and receipt-owned files modified after export;
- stale plan confirmations and target state changes after preview;
- unresolved generated placeholders or missing provider artifacts.

Application stages all bytes, preserves prior owned files in a transaction backup, and
restores them on interruption or failure. Re-export and uninstall use hashes from the
receipt. They do not infer ownership from filenames or directories.

## Runtime ownership

A dual-provider manifest selects one `runtime_owner`. The owner may carry the shared
lifecycle implementation; the non-owner compiles discovery and dispatch artifacts only.
This prevents two adapters from reacting to the same lifecycle event or making duplicate
writes.

Runtime ownership does not make provider permissions portable. A Claude hook cannot be
claimed as Codex enforcement, and a Codex sandbox setting cannot be claimed as a Claude
file-scope firewall. Even on Claude, the hook gates automatic approval eligibility; a
human can still approve a deferred out-of-scope operation.

## Private state and secrets

The vendoring collector accepts only static regular files inside approved runtime
directories and rejects symlinks. Snapshot planning excludes `.squad/partner.md`,
`.env*`, workspaces, engagement records, secrets, caches, version-control state, and
other live/private material by default.

Generated provider instructions strip environment variable values; at most they identify
the variable names a role expects. They also omit live context-source locations and tool
install/verification commands. Authored squad and role goals are copied only through the
canonical `.squad/goal.md` and `.squad/role-goal-<id>.md` context snapshots. A canonical
environment entry is not permission to copy its live details into a prompt or package.

Before release, run a secret scan over tracked changes and generated fixtures. Generated
packages should contain only the canonical roles, provider artifacts, selected static
runtime, activation instructions, license, and receipt.

## Platform support

| Platform | Status | Reason |
| --- | --- | --- |
| macOS | Supported | Primary development and smoke-test platform |
| Linux (Ubuntu) | Supported | Bash, Python, provider artifact tests in CI |
| Windows | Unsupported | Shared runtime and validation gates depend on Bash |

Support refers to this project’s runtime, not every external provider feature. Provider
CLIs may impose their own platform, authentication, model, or feature availability.

## Official provider contracts

- Claude Code project/user/session agent discovery:
  [Subagents](https://code.claude.com/docs/en/sub-agents)
- Claude Code plugin structure and namespacing:
  [Plugins reference](https://code.claude.com/docs/en/plugins-reference)
- Codex standalone plugin structure:
  [Build plugins](https://developers.openai.com/plugins/build/plugins)

Generated Codex packages include a local marketplace whose source is constrained to the
vendored `./plugins/<squad-namespace>` directory. Export validation checks that path and the
nested manifest name/version before activation. Generation never runs the marketplace-add
or plugin-add commands, and this release made no public marketplace submission.

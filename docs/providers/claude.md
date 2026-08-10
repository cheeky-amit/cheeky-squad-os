# Claude Code provider guide

The Claude adapter compiles active canonical roles into namespaced Markdown agents. It
can also generate a self-contained Claude plugin containing agents, selected skills,
scripts, templates, license, activation instructions, and runtime-owner hooks.

## Discovery destinations

Claude Code documents three direct agent scopes:

- session definitions supplied for the current run;
- project agents under `.claude/agents/`;
- user agents under `~/.claude/agents/`.

Plugin agents live under the generated package’s `agents/` directory and are discovered
through the plugin’s own namespace. The compiler also prefixes role IDs with the stable
squad namespace, so two exported squads do not silently claim the same role name.

Official reference: [Claude Code subagents](https://code.claude.com/docs/en/sub-agents).

## Generated Markdown

Each active role compiles to frontmatter with a namespaced `name`, discovery
`description`, mapped tool allowlist, mapped model, and optional effort. The body carries
purpose, assignment, ownership paths, cadence, provider contract, and truthful guidance
about whether the role is read-only or mutating.

Provider-neutral capabilities are mapped to Claude tools. Capabilities needing an exact
provider tool, such as an external MCP surface, require a Claude override rather than a
guessed mapping.

## Standalone plugin

A plugin export contains `.claude-plugin/plugin.json`, namespaced agents, canonical
contracts, activation instructions, license, receipt, and vendored runtime files. When
`runtime_owner` is `claude`, the generated manifest registers the vendored lifecycle
hooks. When Claude is not the runtime owner, the generated Claude manifest registers no
shared hooks.

Inspect the generated plan and package before activation. To try a generated package for
one run, use Claude Code’s explicit local plugin-directory option. Use an approved
plugin installation flow only if you want persistence.

Generation does not:

- install the plugin;
- enable it;
- add a marketplace;
- publish it;
- submit it to a public marketplace.

Official package fields and component layout:
[Claude Code plugins reference](https://code.claude.com/docs/en/plugins-reference).

## Enforcement boundary

The Claude lifecycle runtime can mechanically gate **automatic approval eligibility**
for the specific Edit/Write and narrow scaffolding surfaces documented in
[ARCHITECTURE.md](../../ARCHITECTURE.md). That claim holds only while the generated
Claude package owns and runs the hooks. An out-of-scope request is deferred to Claude's
normal permission flow, where the human can approve it; the hook is not a file-scope
firewall. An agent file by itself is instructional.

Project, user, and plugin exports remain subject to Claude Code’s active permission and
tool policies. Unsupported or unavailable provider capabilities fail compilation rather
than silently broadening the role.

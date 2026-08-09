# Claude Code notes

Read [AGENTS.md](AGENTS.md) for the complete contributor contract.

This repository is the Claude lifecycle plugin and the provider-neutral squad exporter.
Keep cadence separate from destination, keep provider syntax inside adapters, preview
every filesystem mutation, and never install an exported plugin automatically.

Claude project agents live under `.claude/agents/`; user agents live under
`~/.claude/agents/`; generated plugin agents live under `agents/` and are namespaced.
Only the manifest-selected runtime owner may register shared lifecycle hooks.

Run the complete validation gate in [CONTRIBUTING.md](CONTRIBUTING.md) before shipping.

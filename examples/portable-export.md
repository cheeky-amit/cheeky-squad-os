# Worked example: export one squad to Claude Code and Codex

This example starts with an authored one-time squad and creates a project-local,
dual-provider snapshot. It uses an explicit Git repository target and stops before any
user-level or standalone plugin installation.

## 1. Canonical inputs

The roster contains two active roles:

- `evidence-reader`, read-only, owns `reports/evidence/**`;
- `report-writer`, mutating, owns `reports/final/**`.

The manifest keeps cadence and destination separate:

```json
{
  "schema_version": 2,
  "squad": {
    "id": "cheeky-portability-demo",
    "name": "Portability demo",
    "description": "Read evidence and write a final report"
  },
  "execution_mode": "one-time",
  "destination": "project",
  "providers": ["claude", "codex"],
  "runtime_owner": "claude",
  "export_version": "1.1.0"
}
```

## 2. Preview

Run from the selected repository root:

```bash
squad-export plan \
  --manifest .squad/manifest.json \
  --roster .squad/roster.json \
  --target "$PWD" \
  --plan-file /tmp/portability-demo-plan.json
```

Inspect the plan. It should name canonical contracts, receipt, namespaced Claude agent
Markdown, namespaced Codex agent TOML, and Codex repository skills. It must not name
`.squad/partner.md`, `.env*`, workspaces, engagement records, secrets, or a path outside
the repository.

## 3. Confirm and apply

Copy the printed plan ID only after reviewing the complete set:

```bash
squad-export apply \
  --manifest .squad/manifest.json \
  --roster .squad/roster.json \
  --target "$PWD" \
  --plan-file /tmp/portability-demo-plan.json \
  --confirm-plan-id '<reviewed plan_id>'
```

Expected project discovery artifacts include:

```text
.claude/agents/cheeky-portability-demo--evidence-reader.md
.claude/agents/cheeky-portability-demo--report-writer.md
.codex/agents/cheeky-portability-demo--evidence-reader.toml
.codex/agents/cheeky-portability-demo--report-writer.toml
.agents/skills/cheeky-portability-demo-role-evidence-hreader/SKILL.md
.agents/skills/cheeky-portability-demo-role-report-hwriter/SKILL.md
```

The Codex report writer declares `workspace-write` and instructs sequential dispatch.
Its ownership list remains instructional. The Claude package may use the selected
runtime-owner hook when active.

## 4. Validate

```bash
squad-export validate \
  --target "$PWD" \
  --destination project \
  --squad-id cheeky-portability-demo
```

Validation hashes receipt-owned files, parses JSON/TOML, checks provider artifacts, and
rejects unresolved placeholders.

## 5. Re-export or remove

Change canonical inputs, run `plan` again, and review the new writes/deletes. Re-export
will not replace a receipt-owned file that someone modified after generation, and it
will not overwrite an unowned collision.

To remove the unmodified snapshot, preview and save the exact removal plan:

```bash
squad-export uninstall \
  --target "$PWD" \
  --destination project \
  --squad-id cheeky-portability-demo \
  --plan-file /tmp/cheeky-portability-uninstall.json
```

Then review that file and apply only its exact plan ID:

```bash
squad-export uninstall \
  --target "$PWD" \
  --destination project \
  --squad-id cheeky-portability-demo \
  --plan-file /tmp/cheeky-portability-uninstall.json \
  --confirm-plan-id '<reviewed plan_id>'
```

Uninstall preserves modified files and reports them. It never guesses ownership from a
namespaced filename, and it refuses an apply if the saved preview is stale.

## Variations

- Change destination to `session` for prompt-only use with no discovery files.
- Change destination to `user` only when global discovery is intended; apply requires
  `--home`, the exact home target, and `--confirm-global-write`.
- Change destination to `plugin` and target a chosen package directory to generate both
  standalone packages. Then stop and inspect. For Codex, enter the generated directory,
  run `codex plugin marketplace add "$(pwd -P)"`, then run the exact namespaced
  `codex plugin add <plugin>@<marketplace>` command from `ACTIVATION.md`. The exporter
  does not run either activation command.

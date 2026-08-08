from __future__ import annotations

import copy
import json
from dataclasses import replace
from pathlib import Path

import pytest

from cheeky_squad_portability.adapters.claude import (
    claude_role_id,
    compile_claude_agents,
    compile_claude_plugin,
)
from cheeky_squad_portability.contracts import (
    ExecutionMode,
    Provider,
    Roster,
    RuntimeOwner,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError

ROOT = Path(__file__).parents[2]
PORTABLE = ROOT / "tests" / "fixtures" / "portable"
GOLDEN = ROOT / "tests" / "fixtures" / "providers" / "claude"


def _json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture
def manifest() -> SquadManifest:
    return SquadManifest.from_dict(_json(PORTABLE / "manifest-v2.json"))


@pytest.fixture
def roster() -> Roster:
    return Roster.from_dict(_json(PORTABLE / "roster-v2.json"))


@pytest.fixture
def runtime_files() -> dict[str, bytes]:
    return {
        "LICENSE": b"MIT fixture license\n",
        "hooks/session-start.sh": b"#!/bin/sh\n",
        "hooks/user-prompt-submit.sh": b"#!/bin/sh\n",
        "hooks/permission-request.sh": b"#!/bin/sh\n",
        "skills/squad-spawn/SKILL.md": b"# Spawn\n",
        "skills/squad-spawn/scripts/spawn.sh": b"#!/bin/sh\n",
        "templates/goal.md": b"# Goal\n",
        ".env": b"PRIVATE=excluded\n",
        ".squad/partner.md": b"private state\n",
    }


def test_role_ids_are_stably_namespaced(manifest: SquadManifest, roster: Roster) -> None:
    assert claude_role_id(manifest, roster.roles[0]) == "cheeky-portability-demo--evidence-reader"


def test_agents_match_goldens_and_map_read_write_boundaries(
    manifest: SquadManifest, roster: Roster
) -> None:
    artifacts = compile_claude_agents(manifest, roster)

    assert artifacts == {
        "agents/cheeky-portability-demo--evidence-reader.md": (
            GOLDEN / "evidence-reader.md"
        ).read_bytes(),
        "agents/cheeky-portability-demo--report-writer.md": (
            GOLDEN / "report-writer.md"
        ).read_bytes(),
    }
    reader = artifacts["agents/cheeky-portability-demo--evidence-reader.md"].decode()
    writer = artifacts["agents/cheeky-portability-demo--report-writer.md"].decode()
    assert 'tools: ["Read","Glob","Grep"]' in reader
    assert 'model: "haiku"' in reader
    assert "This is a read-only role" in reader
    assert 'tools: ["Read","Write","Edit","Bash"]' in writer
    assert 'model: "opus"' in writer
    assert 'effort: "high"' in writer
    assert "This is a mutating role" in writer
    for text in (reader, writer):
        frontmatter = text.split("---", 2)[1]
        assert "hooks:" not in frontmatter
        assert "mcpServers:" not in frontmatter
        assert "permissionMode:" not in frontmatter


def test_inactive_roles_are_not_discoverable(manifest: SquadManifest, roster: Roster) -> None:
    inactive = replace(roster.roles[0], active=False)
    changed = replace(roster, roles=(inactive, roster.roles[1]))

    artifacts = compile_claude_agents(manifest, changed)

    assert list(artifacts) == ["agents/cheeky-portability-demo--report-writer.md"]


def test_legacy_fallback_is_pure_and_byte_equivalent(manifest: SquadManifest) -> None:
    legacy = _json(PORTABLE / "legacy-roster.json")
    original = copy.deepcopy(legacy)
    canonical = _json(PORTABLE / "roster-v2.json")

    assert compile_claude_agents(manifest, legacy) == compile_claude_agents(manifest, canonical)
    assert legacy == original


def test_plugin_is_self_contained_and_matches_goldens(
    manifest: SquadManifest, roster: Roster, runtime_files: dict[str, bytes]
) -> None:
    artifacts = compile_claude_plugin(manifest, roster, runtime_files)

    assert artifacts[".claude-plugin/plugin.json"] == (GOLDEN / "plugin.json").read_bytes()
    assert artifacts["README.md"] == (GOLDEN / "README.md").read_bytes()
    assert artifacts["skills/squad-spawn/SKILL.md"] == b"# Spawn\n"
    assert artifacts["skills/squad-spawn/scripts/spawn.sh"] == b"#!/bin/sh\n"
    assert artifacts["hooks/permission-request.sh"] == b"#!/bin/sh\n"
    assert artifacts["templates/goal.md"] == b"# Goal\n"
    assert ".env" not in artifacts
    assert ".squad/partner.md" not in artifacts
    assert all(not path.startswith(".claude/agents/") for path in artifacts)


def test_plugin_output_is_deterministic(
    manifest: SquadManifest, roster: Roster, runtime_files: dict[str, bytes]
) -> None:
    reversed_runtime = dict(reversed(tuple(runtime_files.items())))

    assert compile_claude_plugin(manifest, roster, runtime_files) == compile_claude_plugin(
        manifest, roster, reversed_runtime
    )


def test_non_owner_emits_no_claude_hooks(
    manifest: SquadManifest, roster: Roster, runtime_files: dict[str, bytes]
) -> None:
    codex_owned = replace(manifest, runtime_owner=RuntimeOwner.CODEX)

    artifacts = compile_claude_plugin(codex_owned, roster, runtime_files)
    plugin = json.loads(artifacts[".claude-plugin/plugin.json"])

    assert "hooks" not in plugin
    assert not any(path.startswith("hooks/") for path in artifacts)
    assert "registers no lifecycle hooks" in artifacts["README.md"].decode()


def test_claude_owner_requires_complete_runtime_hooks(
    manifest: SquadManifest, roster: Roster, runtime_files: dict[str, bytes]
) -> None:
    del runtime_files["hooks/session-start.sh"]

    with pytest.raises(ContractError, match="missing hook artifact"):
        compile_claude_plugin(manifest, roster, runtime_files)


def test_manifest_and_roster_cadence_must_match(manifest: SquadManifest, roster: Roster) -> None:
    mismatched = replace(roster, execution_mode=ExecutionMode.EVERGREEN)

    with pytest.raises(ContractError, match="execution_mode must match"):
        compile_claude_agents(manifest, mismatched)


def test_claude_must_be_selected(manifest: SquadManifest, roster: Roster) -> None:
    codex_only = replace(
        manifest,
        providers=(Provider.CODEX,),
        runtime_owner=RuntimeOwner.CODEX,
    )

    with pytest.raises(ContractError, match=r"manifest\.providers"):
        compile_claude_agents(codex_only, roster)

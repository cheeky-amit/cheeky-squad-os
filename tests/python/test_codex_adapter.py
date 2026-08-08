from __future__ import annotations

import json
import tomllib
from dataclasses import replace
from pathlib import Path

import pytest

from cheeky_squad_portability.adapters.codex import (
    codex_role_id,
    compile_codex_agents,
    compile_codex_plugin,
    compile_codex_skills,
)
from cheeky_squad_portability.contracts import (
    CodexOverride,
    ExecutionMode,
    Provider,
    ProviderOverrides,
    ReasoningEffort,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError

ROOT = Path(__file__).parents[2]
PORTABLE_FIXTURES = ROOT / "tests" / "fixtures" / "portable"
CODEX_FIXTURES = ROOT / "tests" / "fixtures" / "providers" / "codex"


def load_contracts() -> tuple[SquadManifest, Roster]:
    manifest = SquadManifest.from_dict(
        json.loads((PORTABLE_FIXTURES / "manifest-v2.json").read_text(encoding="utf-8"))
    )
    roster = Roster.from_dict(
        json.loads((PORTABLE_FIXTURES / "roster-v2.json").read_text(encoding="utf-8"))
    )
    return manifest, roster


def test_agents_match_golden_and_parse_as_toml() -> None:
    manifest, roster = load_contracts()

    agents = compile_codex_agents(manifest, roster)

    expected_paths = {
        "agents/cheeky-portability-demo--evidence-reader.toml",
        "agents/cheeky-portability-demo--report-writer.toml",
    }
    assert set(agents) == expected_paths
    for path, content in agents.items():
        assert content == (CODEX_FIXTURES / path).read_bytes()
        parsed = tomllib.loads(content.decode("utf-8"))
        assert {"name", "description", "developer_instructions"} <= parsed.keys()


def test_read_only_and_writing_roles_get_truthful_sandboxes() -> None:
    manifest, roster = load_contracts()
    agents = compile_codex_agents(manifest, roster)

    reader = tomllib.loads(
        agents["agents/cheeky-portability-demo--evidence-reader.toml"].decode("utf-8")
    )
    writer = tomllib.loads(
        agents["agents/cheeky-portability-demo--report-writer.toml"].decode("utf-8")
    )

    assert reader["sandbox_mode"] == "read-only"
    assert reader["model_reasoning_effort"] == "low"
    assert writer["sandbox_mode"] == "workspace-write"
    assert writer["model_reasoning_effort"] == "high"
    assert "instructional coordination boundary" in writer["developer_instructions"]
    assert "not mechanically enforced" in writer["developer_instructions"]
    assert "Dispatch it sequentially" in writer["developer_instructions"]


def test_codex_override_maps_model_effort_and_safe_sandbox() -> None:
    manifest, roster = load_contracts()
    reader = replace(
        roster.roles[0],
        provider_overrides=ProviderOverrides(
            codex=CodexOverride(
                model="gpt-test",
                reasoning_effort=ReasoningEffort.XHIGH,
                sandbox_mode="workspace-write",
            )
        ),
    )
    overridden = replace(roster, roles=(reader,))

    content = next(iter(compile_codex_agents(manifest, overridden).values()))
    parsed = tomllib.loads(content.decode("utf-8"))

    assert parsed["model"] == "gpt-test"
    assert parsed["model_reasoning_effort"] == "xhigh"
    assert parsed["sandbox_mode"] == "workspace-write"


def test_mutating_role_rejects_contradictory_sandbox_override() -> None:
    manifest, roster = load_contracts()
    writer = replace(
        roster.roles[1],
        provider_overrides=ProviderOverrides(codex=CodexOverride(sandbox_mode="read-only")),
    )

    with pytest.raises(ContractError, match="must use Codex sandbox_mode workspace-write"):
        compile_codex_agents(manifest, replace(roster, roles=(writer,)))


def test_repo_and_user_skills_are_namespaced_and_prompt_baked() -> None:
    manifest, roster = load_contracts()

    skills = compile_codex_skills(manifest, roster)

    assert set(skills) == {
        "skills/cheeky-portability-demo--evidence-reader/SKILL.md",
        "skills/cheeky-portability-demo--report-writer/SKILL.md",
    }
    for path, content in skills.items():
        role_id = Path(path).parent.name
        assert content.startswith(f"---\nname: {role_id}\n".encode())
        assert b"Apply the following packaged role instructions" in content


def test_plugin_matches_goldens_and_uses_sequential_prompt_dispatch() -> None:
    manifest, roster = load_contracts()

    plugin = compile_codex_plugin(
        manifest,
        roster,
        {"scripts/run.sh": b"#!/bin/sh\n", "templates/report.md": b"# Report\n"},
    )

    assert (
        plugin[".codex-plugin/plugin.json"]
        == (CODEX_FIXTURES / "plugin" / ".codex-plugin" / "plugin.json").read_bytes()
    )
    dispatch_path = "skills/cheeky-portability-demo--dispatch/SKILL.md"
    assert plugin[dispatch_path] == (CODEX_FIXTURES / "plugin" / dispatch_path).read_bytes()
    assert not any(path.startswith("agents/") or "/agents/" in path for path in plugin)
    assert plugin["runtime/scripts/run.sh"] == b"#!/bin/sh\n"
    assert plugin["runtime/templates/report.md"] == b"# Report\n"
    dispatch = plugin[dispatch_path].decode("utf-8")
    assert "prompt-bakes the packaged roles" in dispatch
    assert "Run every mutating role sequentially" in dispatch
    assert "report-writer (mutating, sequential)" in dispatch


@pytest.mark.parametrize(
    "path",
    ["../escape", "/absolute", "nested/../../escape", r"bad\\path", "not//normalized"],
)
def test_plugin_rejects_unsafe_runtime_paths(path: str) -> None:
    manifest, roster = load_contracts()

    with pytest.raises(ContractError, match="normalized relative path without traversal"):
        compile_codex_plugin(manifest, roster, {path: b"unsafe"})


def test_compiler_requires_codex_and_matching_execution_mode() -> None:
    manifest, roster = load_contracts()
    claude_only = replace(
        manifest,
        providers=(Provider.CLAUDE,),
    )
    mismatched = replace(roster, execution_mode=ExecutionMode.EVERGREEN)

    with pytest.raises(ContractError, match="must select codex"):
        compile_codex_agents(claude_only, roster)
    with pytest.raises(ContractError, match="execution modes must match"):
        compile_codex_agents(manifest, mismatched)


def test_inactive_roles_are_not_compiled_and_ids_are_stable() -> None:
    manifest, roster = load_contracts()
    inactive_writer = replace(roster.roles[1], active=False)
    reduced = replace(roster, roles=(roster.roles[0], inactive_writer))

    first = compile_codex_agents(manifest, reduced)
    second = compile_codex_agents(manifest, reduced)

    assert first == second
    assert codex_role_id(manifest, roster.roles[0]) == "cheeky-portability-demo--evidence-reader"
    assert list(first) == ["agents/cheeky-portability-demo--evidence-reader.toml"]


def test_long_namespaced_role_ids_are_bounded_and_deterministic() -> None:
    manifest, roster = load_contracts()
    long_manifest = replace(
        manifest,
        squad=replace(
            manifest.squad,
            id="namespace-with-a-very-long-prefix.namespace-with-another-very-long-prefix",
        ),
    )

    first = codex_role_id(long_manifest, roster.roles[0])
    second = codex_role_id(long_manifest, roster.roles[0])

    assert first == second
    assert len(first) <= 64
    assert first.startswith("namespace-with-a-very-long-prefix-namespace-with")

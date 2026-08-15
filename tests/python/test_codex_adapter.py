from __future__ import annotations

import json
import os
import re
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
    Destination,
    ExecutionMode,
    OnboardedSkill,
    Provider,
    ProviderOverrides,
    ReasoningEffort,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.namespace import (
    provider_dispatch_skill_id,
    provider_namespace,
    provider_role_skill_id,
)

ROOT = Path(__file__).parents[2]
PORTABLE_FIXTURES = ROOT / "tests" / "fixtures" / "portable"
CODEX_FIXTURES = ROOT / "tests" / "fixtures" / "providers" / "codex"
NAMESPACE = "cheeky-dportability-hdemo"
READER_ID = f"{NAMESPACE}--evidence-reader"
WRITER_ID = f"{NAMESPACE}--report-writer"
READER_SKILL_ID = f"{NAMESPACE}-role-evidence-hreader"
WRITER_SKILL_ID = f"{NAMESPACE}-role-report-hwriter"
DISPATCH_SKILL_ID = f"{NAMESPACE}-squad-dispatch"


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
        f"agents/{READER_ID}.toml",
        f"agents/{WRITER_ID}.toml",
    }
    assert set(agents) == expected_paths
    for path, content in agents.items():
        fixture_name = "evidence-reader.toml" if "evidence-reader" in path else "report-writer.toml"
        assert content == (CODEX_FIXTURES / "agents" / fixture_name).read_bytes()
        parsed = tomllib.loads(content.decode("utf-8"))
        assert {"name", "description", "developer_instructions"} <= parsed.keys()


def test_read_only_and_writing_roles_get_truthful_sandboxes() -> None:
    manifest, roster = load_contracts()
    agents = compile_codex_agents(manifest, roster)

    reader = tomllib.loads(agents[f"agents/{READER_ID}.toml"].decode("utf-8"))
    writer = tomllib.loads(agents[f"agents/{WRITER_ID}.toml"].decode("utf-8"))

    assert reader["sandbox_mode"] == "read-only"
    assert reader["model_reasoning_effort"] == "low"
    assert writer["sandbox_mode"] == "workspace-write"
    assert writer["model_reasoning_effort"] == "high"
    assert "instructional coordination boundary" in writer["developer_instructions"]
    assert "not mechanically enforced" in writer["developer_instructions"]
    assert "Dispatch it sequentially" in writer["developer_instructions"]
    assert "Onboarded skills for this role:" in writer["developer_instructions"]
    assert "citation-formatter (knowledge)" in writer["developer_instructions"]
    assert "docx-export-cli (execution)" in writer["developer_instructions"]
    assert "Onboarded skills for this role:" not in reader["developer_instructions"]


def test_onboarded_skill_with_no_source_url_attributes_as_original() -> None:
    manifest, roster = load_contracts()
    writer = next(role for role in roster.roles if role.id == "report-writer")
    original_skill = replace(
        writer,
        onboarded_skills=(
            OnboardedSkill(
                name="in-house-tool",
                local_path=".squad/skills/report-writer/in-house-tool/SKILL.md",
                purpose="A skill authored fresh for this squad",
                approval_mode="auto",
            ),
        ),
    )
    solo = replace(roster, roles=(original_skill,))

    content = next(iter(compile_codex_agents(manifest, solo).values())).decode("utf-8")

    assert "in-house-tool (knowledge)" in content
    assert "(source: original)" in content


def test_codex_override_maps_model_effort_and_safe_sandbox() -> None:
    manifest, roster = load_contracts()
    reader = replace(
        roster.roles[0],
        provider_overrides=ProviderOverrides(
            codex=CodexOverride(
                model="gpt-test",
                reasoning_effort=ReasoningEffort.XHIGH,
                sandbox_mode="read-only",
            )
        ),
    )
    overridden = replace(roster, roles=(reader,))

    content = next(iter(compile_codex_agents(manifest, overridden).values()))
    parsed = tomllib.loads(content.decode("utf-8"))

    assert parsed["model"] == "gpt-test"
    assert parsed["model_reasoning_effort"] == "xhigh"
    assert parsed["sandbox_mode"] == "read-only"


def test_mutating_role_rejects_contradictory_sandbox_override() -> None:
    manifest, roster = load_contracts()
    writer = replace(
        roster.roles[1],
        provider_overrides=ProviderOverrides(codex=CodexOverride(sandbox_mode="read-only")),
    )

    with pytest.raises(ContractError, match="must use Codex sandbox_mode workspace-write"):
        compile_codex_agents(manifest, replace(roster, roles=(writer,)))


def test_read_only_role_rejects_write_capable_sandbox_override() -> None:
    manifest, roster = load_contracts()
    reader = replace(
        roster.roles[0],
        provider_overrides=ProviderOverrides(codex=CodexOverride(sandbox_mode="workspace-write")),
    )

    with pytest.raises(ContractError, match="must use Codex sandbox_mode read-only"):
        compile_codex_agents(manifest, replace(roster, roles=(reader,)))


def test_danger_full_access_is_not_a_portable_override() -> None:
    with pytest.raises(ContractError, match="sandbox_mode is invalid"):
        CodexOverride(sandbox_mode="danger-full-access")


def test_repo_and_user_skills_are_namespaced_and_prompt_baked() -> None:
    manifest, roster = load_contracts()

    skills = compile_codex_skills(manifest, roster)

    assert set(skills) == {
        f"skills/{READER_SKILL_ID}/SKILL.md",
        f"skills/{WRITER_SKILL_ID}/SKILL.md",
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
        {
            "LICENSE": b"MIT fixture license\n",
            "scripts/run.sh": b"#!/bin/sh\n",
            "templates/report.md": b"# Report\n",
        },
    )

    assert (
        plugin[".codex-plugin/plugin.json"]
        == (CODEX_FIXTURES / "plugin" / ".codex-plugin" / "plugin.json").read_bytes()
    )
    assert (
        plugin[".agents/plugins/marketplace.json"]
        == (CODEX_FIXTURES / "plugin" / ".agents/plugins/marketplace.json").read_bytes()
    )
    marketplace = json.loads(plugin[".agents/plugins/marketplace.json"])
    assert marketplace["name"] == NAMESPACE
    assert marketplace["plugins"] == [
        {
            "category": "Productivity",
            "name": NAMESPACE,
            "policy": {
                "authentication": "ON_INSTALL",
                "installation": "AVAILABLE",
            },
            "source": {"path": f"./plugins/{NAMESPACE}", "source": "local"},
        }
    ]
    nested_prefix = f"plugins/{NAMESPACE}/"
    nested = {
        path.removeprefix(nested_prefix): content
        for path, content in plugin.items()
        if path.startswith(nested_prefix)
    }
    top_level = {
        path: content
        for path, content in plugin.items()
        if path != ".agents/plugins/marketplace.json" and not path.startswith(nested_prefix)
    }
    assert nested == top_level
    dispatch_path = f"skills/{DISPATCH_SKILL_ID}/SKILL.md"
    assert plugin[dispatch_path] == (CODEX_FIXTURES / "plugin" / dispatch_path).read_bytes()
    assert not any(path.startswith("agents/") or "/agents/" in path for path in plugin)
    assert plugin["runtime/scripts/run.sh"] == b"#!/bin/sh\n"
    assert plugin["runtime/templates/report.md"] == b"# Report\n"
    assert plugin["LICENSE"] == b"MIT fixture license\n"
    assert "runtime/LICENSE" not in plugin
    dispatch = plugin[dispatch_path].decode("utf-8")
    assert "prompt-bakes the packaged roles" in dispatch
    assert "Run every mutating role sequentially" in dispatch
    assert "report-writer (mutating, sequential)" in dispatch
    assert "Required vendored context" in dispatch
    assert ".squad/exports/cheeky-dportability-hdemo/context/index.json" in dispatch
    assert "stop before dispatch" in dispatch
    assert "Never substitute live `.squad/goal.md`" in dispatch


@pytest.mark.parametrize(
    "path",
    ["../escape", "/absolute", "nested/../../escape", r"bad\\path", "not//normalized"],
)
def test_plugin_rejects_unsafe_runtime_paths(path: str) -> None:
    manifest, roster = load_contracts()

    with pytest.raises(ContractError, match="normalized relative path without traversal"):
        compile_codex_plugin(
            manifest,
            roster,
            {"LICENSE": b"MIT\n", path: b"unsafe"},
        )


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
    assert codex_role_id(manifest, roster.roles[0]) == READER_ID
    assert list(first) == [f"agents/{READER_ID}.toml"]


def test_long_namespaced_role_ids_are_bounded_and_deterministic() -> None:
    manifest, roster = load_contracts()
    long_manifest = replace(
        manifest,
        squad=replace(
            manifest.squad,
            id="a-b.c-d.e-f.g-h.i-j.k-l.m-n.o-p.q-r.s-t.u-v.w-x.y-z.abc",
        ),
    )

    first = codex_role_id(long_manifest, roster.roles[0])
    second = codex_role_id(long_manifest, roster.roles[0])

    assert first == second
    assert len(provider_namespace(long_manifest.squad.id)) <= 31
    assert len(first) <= 64
    assert first.startswith(f"{provider_namespace(long_manifest.squad.id)}--")


def test_maximum_length_role_skills_remain_validly_bounded() -> None:
    manifest, roster = load_contracts()
    long_manifest = replace(manifest, squad=replace(manifest.squad, id="a-b." * 15 + "abc"))
    long_role = replace(roster.roles[0], id="r" * 64)
    long_roster = replace(roster, roles=(long_role,))

    plugin = compile_codex_plugin(
        long_manifest,
        long_roster,
        {"LICENSE": b"MIT fixture license\n"},
    )
    namespace = provider_namespace(long_manifest.squad.id)
    role_id = codex_role_id(long_manifest, long_role)

    assert len(namespace) <= 31
    assert len(role_id) <= 64
    skill_id = provider_role_skill_id(long_manifest.squad.id, long_role.id)
    dispatch_id = provider_dispatch_skill_id(long_manifest.squad.id)
    assert len(skill_id) <= 64
    assert "--" not in skill_id
    assert f"plugins/{namespace}/skills/{skill_id}/SKILL.md" in plugin
    assert f"plugins/{namespace}/skills/{dispatch_id}/SKILL.md" in plugin

    nested_manifest = json.loads(plugin[f"plugins/{namespace}/.codex-plugin/plugin.json"])
    assert len(nested_manifest["name"]) <= 64
    assert len(nested_manifest["interface"]["displayName"]) <= 64
    assert len(nested_manifest["interface"]["shortDescription"]) <= 96
    assert len(nested_manifest["interface"]["longDescription"]) <= 1024
    assert len(nested_manifest["interface"]["defaultPrompt"]) <= 3
    assert all(len(prompt) <= 128 for prompt in nested_manifest["interface"]["defaultPrompt"])


def test_role_named_dispatch_cannot_collide_with_dispatcher() -> None:
    manifest, _ = load_contracts()

    role_skill = provider_role_skill_id(manifest.squad.id, "dispatch")
    dispatch_skill = provider_dispatch_skill_id(manifest.squad.id)

    assert role_skill != dispatch_skill
    assert role_skill.endswith("-role-dispatch")
    assert dispatch_skill.endswith("-squad-dispatch")


def _assert_quick_validate_compatible_skill(path: str, content: bytes) -> None:
    folder = Path(path).parent.name
    text = content.decode("utf-8")
    frontmatter = text.split("---\n", 2)[1]
    fields = dict(line.split(": ", 1) for line in frontmatter.splitlines())
    name = fields["name"]
    description = json.loads(fields["description"])

    assert name == folder
    assert re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name)
    assert len(name) <= 64
    assert "<" not in description and ">" not in description
    assert len(description) <= 1024


def test_short_and_max_packages_have_quick_validate_compatible_skills() -> None:
    manifest, roster = load_contracts()
    long_manifest = replace(
        manifest,
        squad=replace(
            manifest.squad,
            id="a-b." * 15 + "abc",
            name="Long <squad> " + "n" * 1100,
            description="Long portable description " + "d" * 1100,
        ),
    )
    long_role = replace(
        roster.roles[0],
        id="r" * 64,
        description="Read <private> evidence " + "x" * 1100,
    )
    packages = (
        compile_codex_plugin(manifest, roster, {"LICENSE": b"MIT\n"}),
        compile_codex_plugin(
            long_manifest,
            replace(roster, roles=(long_role,)),
            {"LICENSE": b"MIT\n"},
        ),
    )

    for package in packages:
        skills = {
            path: content
            for path, content in package.items()
            if path.startswith("skills/") and path.endswith("/SKILL.md")
        }
        assert skills
        for path, content in skills.items():
            _assert_quick_validate_compatible_skill(path, content)


def test_destination_specific_context_paths_are_prompt_baked() -> None:
    manifest, roster = load_contracts()
    namespace = provider_namespace(manifest.squad.id)

    project = next(iter(compile_codex_agents(manifest, roster).values())).decode()
    user = next(
        iter(compile_codex_agents(replace(manifest, destination=Destination.USER), roster).values())
    ).decode()
    plugin = compile_codex_plugin(
        replace(manifest, destination=Destination.PLUGIN),
        roster,
        {"LICENSE": b"MIT\n"},
    )
    dispatch = plugin[f"skills/{DISPATCH_SKILL_ID}/SKILL.md"].decode()

    assert f".squad/exports/{namespace}/context/index.json" in project
    assert f"${{HOME}}/.squad/squads/{namespace}/context/index.json" in user
    assert ".squad/context/index.json" in dispatch
    assert "status; do not work" in project


def test_user_agent_resolves_snapshot_from_home_outside_current_repo(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    manifest, roster = load_contracts()
    fake_home = tmp_path / "fresh-home"
    unrelated = tmp_path / "unrelated-repository"
    fake_home.mkdir()
    unrelated.mkdir()
    monkeypatch.setenv("HOME", str(fake_home))
    monkeypatch.chdir(unrelated)
    namespace = provider_namespace(manifest.squad.id)
    anchor = f"${{HOME}}/.squad/squads/{namespace}"
    context_root = Path(os.path.expandvars(anchor)) / "context"
    context_root.mkdir(parents=True)
    (context_root / "index.json").write_text("{}\n", encoding="utf-8")

    user_manifest = replace(manifest, destination=Destination.USER)
    user = next(iter(compile_codex_agents(user_manifest, roster).values())).decode()

    assert f"{anchor}/context/index.json" in user
    assert str(unrelated) not in user
    assert "from .squad/squads/" not in user
    assert "when that file is available" not in user
    assert (Path(os.path.expandvars(anchor)) / "context/index.json").is_file()


def test_root_codex_manifest_is_structural_and_does_not_claim_lifecycle_skills() -> None:
    manifest = json.loads((ROOT / ".codex-plugin/plugin.json").read_text())

    assert "skills" not in manifest
    assert "Structural metadata" in manifest["description"]
    assert "Claude lifecycle" in manifest["interface"]["longDescription"]


def test_namespace_encoding_is_injective_for_dots_and_hyphens() -> None:
    manifest, roster = load_contracts()
    dotted = replace(manifest, squad=replace(manifest.squad, id="foo.bar"))
    hyphenated = replace(manifest, squad=replace(manifest.squad, id="foo-bar"))

    assert provider_namespace(dotted.squad.id) != provider_namespace(hyphenated.squad.id)
    assert codex_role_id(dotted, roster.roles[0]) != codex_role_id(hyphenated, roster.roles[0])


def test_legacy_roster_compiles_identically_for_codex() -> None:
    manifest, roster = load_contracts()
    legacy = json.loads((PORTABLE_FIXTURES / "legacy-roster.json").read_text(encoding="utf-8"))
    # roster-v2.json carries a v2-only onboarded_skills entry that a legacy
    # roster has no way to express; strip it before comparing compiled output.
    portable_only = replace(
        roster,
        roles=tuple(replace(role, onboarded_skills=()) for role in roster.roles),
    )

    assert compile_codex_agents(manifest, legacy) == compile_codex_agents(manifest, portable_only)


def test_generated_codex_artifacts_never_embed_environment_values() -> None:
    manifest, roster = load_contracts()
    sentinel = "portable-secret-sentinel"
    environment = replace(
        roster.roles[1].environment,
        variables=(("API_TOKEN", sentinel),),
        tools=(
            replace(
                roster.roles[1].environment.tools[0],
                verify=f"verify --token {sentinel}",
                install=f"install --token {sentinel}",
            ),
        ),
    )
    writer = replace(roster.roles[1], environment=environment)
    reduced = replace(roster, roles=(writer,))

    artifacts = {
        **compile_codex_agents(manifest, reduced),
        **compile_codex_skills(manifest, reduced),
        **compile_codex_plugin(manifest, reduced, {"LICENSE": b"MIT\n"}),
    }

    assert any(b"API_TOKEN" in content for content in artifacts.values())
    assert all(sentinel.encode() not in content for content in artifacts.values())


@pytest.mark.parametrize("path", [".env", ".squad/partner.md", "workspaces/live/env"])
def test_plugin_rejects_private_runtime_paths(path: str) -> None:
    manifest, roster = load_contracts()

    with pytest.raises(ContractError, match="private or live state"):
        compile_codex_plugin(manifest, roster, {"LICENSE": b"MIT\n", path: b"secret"})


def test_plugin_requires_license() -> None:
    manifest, roster = load_contracts()

    with pytest.raises(ContractError, match="requires LICENSE"):
        compile_codex_plugin(manifest, roster, {"scripts/run.sh": b"#!/bin/sh\n"})

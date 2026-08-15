from __future__ import annotations

import copy
import json
import os
from dataclasses import replace
from pathlib import Path

import pytest

from cheeky_squad_portability.adapters.claude import (
    claude_role_id,
    compile_claude_agents,
    compile_claude_plugin,
)
from cheeky_squad_portability.contracts import (
    Destination,
    ExecutionMode,
    OnboardedSkill,
    Provider,
    Roster,
    RuntimeOwner,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.namespace import provider_namespace

ROOT = Path(__file__).parents[2]
PORTABLE = ROOT / "tests" / "fixtures" / "portable"
GOLDEN = ROOT / "tests" / "fixtures" / "providers" / "claude"
NAMESPACE = "cheeky-dportability-hdemo"
READER_ID = f"{NAMESPACE}--evidence-reader"
WRITER_ID = f"{NAMESPACE}--report-writer"


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
        "commands/squad-workflow.md": b"# Workflow\n",
        "skills/squad-spawn/SKILL.md": b"# Spawn\n",
        "skills/squad-spawn/scripts/spawn.sh": b"#!/bin/sh\n",
        "templates/goal.md": b"# Goal\n",
        ".env": b"PRIVATE=excluded\n",
        ".squad/partner.md": b"private state\n",
    }


def test_role_ids_are_stably_namespaced(manifest: SquadManifest, roster: Roster) -> None:
    assert claude_role_id(manifest, roster.roles[0]) == READER_ID


def test_agents_match_goldens_and_map_read_write_boundaries(
    manifest: SquadManifest, roster: Roster
) -> None:
    artifacts = compile_claude_agents(manifest, roster)

    assert artifacts == {
        f"agents/{READER_ID}.md": (GOLDEN / "evidence-reader.md").read_bytes(),
        f"agents/{WRITER_ID}.md": (GOLDEN / "report-writer.md").read_bytes(),
    }
    reader = artifacts[f"agents/{READER_ID}.md"].decode()
    writer = artifacts[f"agents/{WRITER_ID}.md"].decode()
    assert 'tools: ["Read","Glob","Grep"]' in reader
    assert 'model: "haiku"' in reader
    assert "This is a read-only role" in reader
    assert 'tools: ["Read","Write","Edit","Bash"]' in writer
    assert 'model: "opus"' in writer
    assert 'effort: "high"' in writer
    assert "This is a mutating role" in writer
    assert ".squad/role-plan-report-writer.md" in writer
    assert "Expected variable names: `REPORT_FORMAT`" in writer
    assert "REPORT_FORMAT=markdown" not in writer
    assert "## Onboarded skills" in writer
    assert "`citation-formatter`" in writer
    assert ".squad/skills/report-writer/citation-formatter/SKILL.md" in writer
    assert "source: https://github.com/anthropics/skills" in writer
    assert "## Onboarded skills" not in reader
    for text in (reader, writer):
        frontmatter = text.split("---", 2)[1]
        assert "hooks:" not in frontmatter
        assert "mcpServers:" not in frontmatter
        assert "permissionMode:" not in frontmatter


def test_onboarded_skill_with_no_source_url_attributes_as_original(
    manifest: SquadManifest, roster: Roster
) -> None:
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

    artifacts = compile_claude_agents(manifest, solo)
    content = next(iter(artifacts.values())).decode()

    assert "`in-house-tool`" in content
    assert "(source: original)" in content


def test_agents_load_vendored_context_from_destination_anchors_outside_cwd(
    manifest: SquadManifest,
    roster: Roster,
    runtime_files: dict[str, bytes],
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    unrelated = tmp_path / "unrelated-working-directory"
    project_root = tmp_path / "selected-project"
    fake_home = tmp_path / "fresh-home"
    plugin_root = tmp_path / "portable-plugin"
    for root in (unrelated, project_root, fake_home, plugin_root):
        root.mkdir()
    monkeypatch.chdir(unrelated)
    monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(project_root))
    monkeypatch.setenv("HOME", str(fake_home))
    monkeypatch.setenv("CLAUDE_PLUGIN_ROOT", str(plugin_root))

    namespace = provider_namespace(manifest.squad.id)
    cases = (
        (
            Destination.PROJECT,
            f"${{CLAUDE_PROJECT_DIR}}/.squad/exports/{namespace}",
            compile_claude_agents,
        ),
        (
            Destination.USER,
            f"${{HOME}}/.squad/squads/{namespace}",
            compile_claude_agents,
        ),
        (Destination.PLUGIN, "${CLAUDE_PLUGIN_ROOT}/.squad", compile_claude_plugin),
    )
    for destination, anchor, compiler in cases:
        context_root = Path(os.path.expandvars(anchor)) / "context"
        (context_root / "roles").mkdir(parents=True)
        (context_root / "index.json").write_text("{}\n", encoding="utf-8")
        (context_root / "squad-goal.md").write_text("squad goal\n", encoding="utf-8")
        (context_root / "roles/evidence-reader.md").write_text("reader goal\n", encoding="utf-8")
        destination_manifest = replace(manifest, destination=destination)
        if compiler is compile_claude_plugin:
            artifacts = compiler(destination_manifest, roster, runtime_files)
        else:
            artifacts = compiler(destination_manifest, roster)
        reader = artifacts[f"agents/{READER_ID}.md"].decode()

        assert f"{anchor}/context/index.json" in reader
        assert str(unrelated) not in reader
        assert "Require exactly one `role_goals` entry" in reader
        assert "stop before working" in reader
        assert "Never fall back to live `.squad/goal.md`" in reader
        assert (Path(os.path.expandvars(anchor)) / "context/index.json").is_file()


def test_inactive_roles_are_not_discoverable(manifest: SquadManifest, roster: Roster) -> None:
    inactive = replace(roster.roles[0], active=False)
    changed = replace(roster, roles=(inactive, roster.roles[1]))

    artifacts = compile_claude_agents(manifest, changed)

    assert list(artifacts) == [f"agents/{WRITER_ID}.md"]


def test_legacy_fallback_is_pure_and_byte_equivalent(manifest: SquadManifest) -> None:
    legacy = _json(PORTABLE / "legacy-roster.json")
    original = copy.deepcopy(legacy)
    canonical = _json(PORTABLE / "roster-v2.json")
    # roster-v2.json carries a v2-only onboarded_skills entry that a legacy
    # roster has no way to express; strip it before comparing compiled output.
    assert isinstance(canonical, dict)
    canonical_roles = canonical["roles"]
    assert isinstance(canonical_roles, list) and isinstance(canonical_roles[1], dict)
    canonical_roles[1].pop("onboarded_skills", None)

    assert compile_claude_agents(manifest, legacy) == compile_claude_agents(manifest, canonical)
    assert legacy == original


def test_plugin_is_self_contained_and_matches_goldens(
    manifest: SquadManifest, roster: Roster, runtime_files: dict[str, bytes]
) -> None:
    artifacts = compile_claude_plugin(manifest, roster, runtime_files)

    assert artifacts[".claude-plugin/plugin.json"] == (GOLDEN / "plugin.json").read_bytes()
    assert json.loads(artifacts[".squad/provider-role-map.json"]) == {
        "schema_version": 1,
        "roles": {
            READER_ID: "evidence-reader",
            WRITER_ID: "report-writer",
        },
    }
    assert artifacts["README.md"] == (GOLDEN / "README.md").read_bytes()
    assert artifacts["skills/squad-spawn/SKILL.md"] == b"# Spawn\n"
    assert artifacts["skills/squad-spawn/scripts/spawn.sh"] == b"#!/bin/sh\n"
    assert artifacts["commands/squad-workflow.md"] == b"# Workflow\n"
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


def test_namespace_encoding_is_injective_for_dots_and_hyphens(
    manifest: SquadManifest, roster: Roster
) -> None:
    dotted = replace(manifest, squad=replace(manifest.squad, id="foo.bar"))
    hyphenated = replace(manifest, squad=replace(manifest.squad, id="foo-bar"))

    assert provider_namespace(dotted.squad.id) != provider_namespace(hyphenated.squad.id)
    assert claude_role_id(dotted, roster.roles[0]) != claude_role_id(hyphenated, roster.roles[0])


def test_generated_agents_never_embed_environment_values(
    manifest: SquadManifest, roster: Roster
) -> None:
    sentinel = "portable-secret-sentinel"
    environment = replace(
        roster.roles[1].environment,
        variables=(("API_TOKEN", sentinel),),
    )
    writer = replace(roster.roles[1], environment=environment)

    generated = compile_claude_agents(manifest, replace(roster, roles=(writer,)))
    content = next(iter(generated.values()))

    assert b"API_TOKEN" in content
    assert sentinel.encode() not in content


def test_claude_worktree_isolation_compiles_to_agent_frontmatter(
    manifest: SquadManifest, roster: Roster
) -> None:
    role = roster.roles[0]
    assert role.provider_overrides is not None
    assert role.provider_overrides.claude is not None
    override = replace(role.provider_overrides.claude, isolation="worktree")
    providers = replace(role.provider_overrides, claude=override)
    isolated = replace(role, provider_overrides=providers)

    compiled = compile_claude_agents(manifest, replace(roster, roles=(isolated,)))
    content = next(iter(compiled.values()))
    frontmatter = content.decode().split("---", 2)[1]

    assert 'isolation: "worktree"' in frontmatter

from __future__ import annotations

import json
import subprocess
from dataclasses import FrozenInstanceError, replace
from pathlib import Path

import pytest

from cheeky_squad_portability.cli import run_cli
from cheeky_squad_portability.contracts import Destination, Provider, Roster, SquadManifest
from cheeky_squad_portability.exporter import (
    ExportError,
    ProviderCompilers,
    apply_export,
    apply_uninstall_export,
    plan_export,
    plan_uninstall_export,
    squad_namespace,
    validate_installed_export,
    validate_prepared_export,
)
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.receipt import ExportReceipt

ROOT = Path(__file__).parents[2]
FIXTURES = ROOT / "tests" / "fixtures" / "portable"


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def roster() -> Roster:
    return load_roster(load_json(FIXTURES / "roster-v2.json"))


def manifest(
    destination: Destination,
    providers: tuple[Provider, ...] = (Provider.CLAUDE, Provider.CODEX),
) -> SquadManifest:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    raw["destination"] = destination.value
    raw["providers"] = [provider.value for provider in providers]
    if Provider.CLAUDE not in providers:
        raw["runtime_owner"] = Provider.CODEX.value
    return SquadManifest.from_dict(raw)


def claude_agents(squad: SquadManifest, _roster: Roster) -> dict[str, bytes]:
    namespace = squad_namespace(squad.squad.id)
    return {
        f"agents/{namespace}--evidence-reader.md": (
            f"---\nname: {namespace}--evidence-reader\n"
            "description: Read evidence\n---\nRead only.\n"
        ).encode()
    }


def claude_agent_bytes(name: str, version: str) -> bytes:
    return (
        f"---\nname: {name}\ndescription: Read evidence\n---\nInstructions {version}.\n"
    ).encode()


def codex_agents(squad: SquadManifest, _roster: Roster) -> dict[str, bytes]:
    namespace = squad_namespace(squad.squad.id)
    return {
        f"agents/{namespace}--evidence-reader.toml": (
            f'name = "{namespace}--evidence-reader"\n'
            'description = "Read evidence"\n'
            'developer_instructions = "Read only."\n'
        ).encode()
    }


def codex_skills(squad: SquadManifest, _roster: Roster) -> dict[str, bytes]:
    namespace = squad_namespace(squad.squad.id)
    return {
        f"skills/{namespace}-squad-dispatch/SKILL.md": (
            b"# Dispatch\n\nRun mutating roles sequentially.\n"
        )
    }


def claude_plugin(squad: SquadManifest, _roster: Roster, _runtime: object) -> dict[str, bytes]:
    namespace = squad_namespace(squad.squad.id)
    plugin = {
        "name": namespace,
        "description": "Portable squad",
        "version": squad.export_version,
    }
    return {
        ".claude-plugin/plugin.json": (json.dumps(plugin, sort_keys=True) + "\n").encode(),
        f"agents/{namespace}--evidence-reader.md": (
            f"---\nname: {namespace}--evidence-reader\ndescription: Read evidence\n---\nRead.\n"
        ).encode(),
        "runtime/claude-dispatch.md": b"Vendored Claude runtime.\n",
    }


def codex_plugin(squad: SquadManifest, _roster: Roster, _runtime: object) -> dict[str, bytes]:
    namespace = squad_namespace(squad.squad.id)
    plugin = {
        "name": namespace,
        "description": "Portable squad",
        "version": squad.export_version,
    }
    manifest_bytes = (json.dumps(plugin, sort_keys=True) + "\n").encode()
    marketplace = {
        "name": namespace,
        "plugins": [
            {
                "name": namespace,
                "source": {"source": "local", "path": f"./plugins/{namespace}"},
            }
        ],
    }
    return {
        ".agents/plugins/marketplace.json": (
            json.dumps(marketplace, sort_keys=True) + "\n"
        ).encode(),
        ".codex-plugin/plugin.json": manifest_bytes,
        f".agents/skills/{namespace}-squad-dispatch/SKILL.md": (
            b"# Dispatch\n\nUse vendored, prompt-baked roles sequentially for mutations.\n"
        ),
        f"plugins/{namespace}/.codex-plugin/plugin.json": manifest_bytes,
        "runtime/codex-dispatch.md": b"Vendored Codex runtime.\n",
    }


@pytest.fixture
def compilers() -> ProviderCompilers:
    return ProviderCompilers(
        claude_agents=claude_agents,
        claude_plugin=claude_plugin,
        codex_agents=codex_agents,
        codex_skills=codex_skills,
        codex_plugin=codex_plugin,
    )


def repository(tmp_path: Path) -> Path:
    target = tmp_path / "project"
    target.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    return target


def test_project_plan_is_deterministic_confirmed_and_validated(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    arguments = {
        "manifest": manifest(Destination.PROJECT),
        "roster": roster(),
        "compilers": compilers,
        "target_root": target,
    }

    first = plan_export(**arguments)
    second = plan_export(**arguments)

    assert first == second
    assert first.plan.plan_id == second.plan.plan_id
    assert {item.path for item in first.plan.writes} >= {
        ".squad/exports/cheeky-dportability-hdemo/manifest.json",
        ".squad/exports/cheeky-dportability-hdemo/roster.json",
        ".squad/exports/cheeky-dportability-hdemo/export-receipt.json",
    }
    assert not (target / ".squad").exists()
    with pytest.raises(ExportError, match="plan ID"):
        apply_export(first, confirmed_plan_id="0" * 64)

    result = apply_export(first, confirmed_plan_id=first.plan.plan_id)
    report = validate_installed_export(
        target_root=target,
        destination=Destination.PROJECT,
        squad_id=first.plan.manifest.squad.id,
    )

    assert result.written == tuple(sorted(item.path for item in first.plan.writes))
    assert len(report.checked_files) == len(first.plan.writes) - 1
    assert plan_export(**arguments).plan.writes == ()


def test_session_prompt_bakes_roles_without_calling_compilers_or_writing(
    tmp_path: Path,
) -> None:
    called = False

    def forbidden(_manifest: SquadManifest, _roster: Roster) -> dict[str, bytes]:
        nonlocal called
        called = True
        raise AssertionError("session must not compile discovery files")

    prepared = plan_export(
        manifest=manifest(Destination.SESSION),
        roster=roster(),
        compilers=ProviderCompilers(
            claude_agents=forbidden,
            codex_agents=forbidden,
        ),
    )
    result = apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)

    assert prepared.plan.writes == ()
    assert prepared.plan.deletes == ()
    assert prepared.preconditions == ()
    assert called is False
    assert "session only" in result.session_prompt
    assert "report-writer" in result.session_prompt
    assert list(tmp_path.iterdir()) == []


def test_user_requires_global_confirmation_and_namespaces_every_artifact(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    prepared = plan_export(
        manifest=manifest(Destination.USER),
        roster=roster(),
        compilers=compilers,
        target_root=fake_home,
        home=fake_home,
    )
    namespace = squad_namespace(prepared.plan.manifest.squad.id)

    assert all(
        namespace in path
        for path in (
            item.path
            for item in prepared.plan.writes
            if item.path.startswith((".claude/", ".codex/", ".squad/"))
        )
    )
    with pytest.raises(ExportError, match="global-write confirmation"):
        apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    apply_export(
        prepared,
        confirmed_plan_id=prepared.plan.plan_id,
        global_write_confirmed=True,
    )
    validate_installed_export(
        target_root=fake_home,
        home=fake_home,
        destination=Destination.USER,
        squad_id=prepared.plan.manifest.squad.id,
    )


def test_user_rejects_unnamespaced_provider_output(tmp_path: Path) -> None:
    fake_home = tmp_path / "home"
    fake_home.mkdir()

    with pytest.raises(ExportError, match="not namespaced"):
        plan_export(
            manifest=manifest(Destination.USER, (Provider.CLAUDE,)),
            roster=roster(),
            target_root=fake_home,
            home=fake_home,
            compilers=ProviderCompilers(
                claude_agents=lambda _manifest, _roster: {"agents/reader.md": b"# Reader\n"}
            ),
        )


def test_plugin_is_self_contained_and_generation_stops_before_installation(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = tmp_path / "portable-plugin"
    target.mkdir()
    prepared = plan_export(
        manifest=manifest(Destination.PLUGIN),
        roster=roster(),
        compilers=compilers,
        target_root=target,
        home=tmp_path / "unused-home",
        vendored_files={"shared/scripts/dispatch.sh": b"#!/bin/sh\nexit 0\n"},
        executable_paths={"shared/scripts/dispatch.sh"},
    )
    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)

    expected = {
        ".agents/plugins/marketplace.json",
        ".claude-plugin/plugin.json",
        ".codex-plugin/plugin.json",
        ".squad/manifest.json",
        ".squad/roster.json",
        "shared/manifest.json",
        "shared/roster.json",
        "ACTIVATION.md",
        "LICENSE",
    }
    assert expected <= {item.path for item in prepared.plan.writes}
    assert (target / "shared/scripts/dispatch.sh").stat().st_mode & 0o111
    assert not (tmp_path / "unused-home").exists()
    assert b"does not require the squad generator" in (target / "ACTIVATION.md").read_bytes()
    activation = (target / "ACTIVATION.md").read_text()
    assert 'codex plugin marketplace add "$(pwd -P)"' in activation
    assert "codex plugin add cheeky-dportability-hdemo@cheeky-dportability-hdemo" in activation
    validate_installed_export(
        target_root=target,
        destination=Destination.PLUGIN,
        squad_id=prepared.plan.manifest.squad.id,
        home=tmp_path / "unused-home",
    )


@pytest.mark.parametrize(
    "unsafe_path",
    [
        "../escape.txt",
        "/absolute.txt",
        ".env",
        ".envlocal",
        ".env.production",
        ".squad/partner.md",
        ".squad/workspaces/role/private.md",
        "secrets/token.txt",
        "engagement-records/live.json",
    ],
)
def test_export_rejects_traversal_and_private_state(tmp_path: Path, unsafe_path: str) -> None:
    target = repository(tmp_path)

    with pytest.raises(ExportError):
        plan_export(
            manifest=manifest(Destination.PROJECT, (Provider.CLAUDE,)),
            roster=roster(),
            target_root=target,
            compilers=ProviderCompilers(
                claude_agents=lambda squad, _roster: {
                    f"agents/{squad_namespace(squad.squad.id)}--reader.md": b"# Read\n",
                    unsafe_path: b"private",
                }
            ),
        )


def test_export_rejects_unowned_collision_and_symlink_escape(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    source_manifest = target / ".squad/manifest.json"
    source_manifest.parent.mkdir()
    source_manifest.write_text("live authoring source", encoding="utf-8")
    plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )

    collision = target / ".claude/agents/cheeky-dportability-hdemo--evidence-reader.md"
    collision.parent.mkdir(parents=True)
    collision.write_text("user-owned", encoding="utf-8")

    with pytest.raises(ExportError, match="unowned file collision"):
        plan_export(
            manifest=manifest(Destination.PROJECT),
            roster=roster(),
            compilers=compilers,
            target_root=target,
        )

    collision.unlink()
    collision.parent.rmdir()
    collision.parent.parent.rmdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (target / ".claude").symlink_to(outside, target_is_directory=True)
    with pytest.raises(ExportError, match="symlink"):
        plan_export(
            manifest=manifest(Destination.PROJECT),
            roster=roster(),
            compilers=compilers,
            target_root=target,
        )
    assert list(outside.iterdir()) == []


def test_project_and_plugin_reject_home_and_root_targets(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    home = repository(tmp_path)
    with pytest.raises(ExportError, match="home directory"):
        plan_export(
            manifest=manifest(Destination.PROJECT),
            roster=roster(),
            compilers=compilers,
            target_root=home,
            home=home,
        )
    with pytest.raises(ExportError, match="filesystem roots"):
        plan_export(
            manifest=manifest(Destination.PLUGIN),
            roster=roster(),
            compilers=compilers,
            target_root=Path("/"),
            home=home,
        )


def test_reexport_only_updates_and_deletes_unmodified_receipt_owned_files(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    first = plan_export(
        manifest=manifest(Destination.PROJECT, (Provider.CLAUDE,)),
        roster=roster(),
        compilers=ProviderCompilers(
            claude_agents=lambda squad, _roster: {
                f"agents/{squad_namespace(squad.squad.id)}--reader.md": claude_agent_bytes(
                    f"{squad_namespace(squad.squad.id)}--reader", "v1"
                ),
                f"agents/{squad_namespace(squad.squad.id)}--old.md": claude_agent_bytes(
                    f"{squad_namespace(squad.squad.id)}--old", "old"
                ),
            }
        ),
        target_root=target,
    )
    apply_export(first, confirmed_plan_id=first.plan.plan_id)
    namespace = squad_namespace(first.plan.manifest.squad.id)
    changed_path = f".claude/agents/{namespace}--reader.md"
    old_path = f".claude/agents/{namespace}--old.md"
    second = plan_export(
        manifest=first.plan.manifest,
        roster=roster(),
        compilers=ProviderCompilers(
            claude_agents=lambda _manifest, _roster: {
                f"agents/{namespace}--reader.md": claude_agent_bytes(f"{namespace}--reader", "v2")
            }
        ),
        target_root=target,
    )

    assert changed_path in {item.path for item in second.plan.writes}
    assert old_path in {item.path for item in second.plan.deletes}
    apply_export(second, confirmed_plan_id=second.plan.plan_id)
    assert (target / changed_path).read_bytes() == claude_agent_bytes(f"{namespace}--reader", "v2")
    assert not (target / old_path).exists()

    (target / changed_path).write_bytes(b"owner edit\n")
    with pytest.raises(ExportError, match="modified"):
        plan_export(
            manifest=first.plan.manifest,
            roster=roster(),
            compilers=ProviderCompilers(
                claude_agents=lambda _manifest, _roster: {
                    f"agents/{namespace}--reader.md": claude_agent_bytes(
                        f"{namespace}--reader", "v3"
                    )
                }
            ),
            target_root=target,
        )


def test_apply_rechecks_preview_and_rolls_back_on_interruption(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )

    def interrupt(event: str, _path: str) -> None:
        if event == "written":
            raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        apply_export(
            prepared,
            confirmed_plan_id=prepared.plan.plan_id,
            fault_hook=interrupt,
        )
    assert not any(path.is_file() for path in target.rglob("*") if ".git" not in path.parts)

    changed = target / next(item.path for item in prepared.writes if item.path.endswith(".md"))
    changed.parent.mkdir(parents=True, exist_ok=True)
    changed.write_text("appeared after preview\n", encoding="utf-8")
    with pytest.raises(ExportError, match="filesystem changed"):
        apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)


def test_apply_defensively_rejects_hand_built_root_and_symlink_targets(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )
    root_plan = replace(prepared.plan, target_root="/")
    unsafe = replace(prepared, plan=root_plan)
    with pytest.raises(ExportError, match="filesystem roots"):
        apply_export(unsafe, confirmed_plan_id=root_plan.plan_id)

    real_target = tmp_path / "real-project"
    target.rename(real_target)
    target.symlink_to(real_target, target_is_directory=True)
    with pytest.raises(ExportError, match="symlink"):
        apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)


def test_uninstall_preserves_modified_files_and_keeps_reduced_receipt(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )
    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    modified = next(
        item.path for item in prepared.writes if item.path.endswith("evidence-reader.md")
    )
    (target / modified).write_text("human modification\n", encoding="utf-8")

    uninstall = plan_uninstall_export(
        target_root=target,
        destination=Destination.PROJECT,
        squad_id=prepared.plan.manifest.squad.id,
    )
    with pytest.raises(ExportError, match="plan ID"):
        apply_uninstall_export(uninstall, confirmed_plan_id="wrong-plan")
    result = apply_uninstall_export(
        uninstall,
        confirmed_plan_id=uninstall.plan.plan_id,
    )
    receipt_path = target / ".squad/exports/cheeky-dportability-hdemo/export-receipt.json"
    reduced = ExportReceipt.from_bytes(receipt_path.read_bytes())

    assert result.preserved_modified == (modified,)
    assert result.receipt_retained is True
    assert [item.path for item in reduced.files] == [modified]
    assert (target / modified).read_text(encoding="utf-8") == "human modification\n"
    assert not any(path.is_file() for path in (target / ".codex").rglob("*"))


def test_user_uninstall_requires_separate_global_write_confirmation(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    prepared = plan_export(
        manifest=manifest(Destination.USER),
        roster=roster(),
        compilers=compilers,
        target_root=fake_home,
        home=fake_home,
    )
    apply_export(
        prepared,
        confirmed_plan_id=prepared.plan.plan_id,
        global_write_confirmed=True,
    )
    uninstall = plan_uninstall_export(
        target_root=fake_home,
        destination=Destination.USER,
        squad_id=prepared.plan.manifest.squad.id,
        home=fake_home,
    )

    with pytest.raises(ExportError, match="global-write confirmation"):
        apply_uninstall_export(uninstall, confirmed_plan_id=uninstall.plan.plan_id)
    result = apply_uninstall_export(
        uninstall,
        confirmed_plan_id=uninstall.plan.plan_id,
        global_write_confirmed=True,
    )

    assert result.receipt_retained is False
    assert not any(path.is_file() for path in fake_home.rglob("*"))


def test_validate_detects_hash_tampering_and_placeholders(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )
    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    tampered = next(item.path for item in prepared.writes if item.path.endswith(".toml"))
    (target / tampered).write_text("tampered", encoding="utf-8")
    with pytest.raises(ExportError, match="does not match"):
        validate_installed_export(
            target_root=target,
            destination=Destination.PROJECT,
            squad_id=prepared.plan.manifest.squad.id,
        )

    fresh = repository(tmp_path / "other")
    with pytest.raises(ExportError, match="placeholder"):
        plan_export(
            manifest=manifest(Destination.PROJECT, (Provider.CLAUDE,)),
            roster=roster(),
            target_root=fresh,
            compilers=ProviderCompilers(
                claude_agents=lambda squad, _roster: {
                    f"agents/{squad_namespace(squad.squad.id)}--reader.md": (
                        b"{{ROLE_INSTRUCTIONS}}\n"
                    )
                }
            ),
        )


def test_provider_and_engine_owned_collisions_fail_safely(tmp_path: Path) -> None:
    target = tmp_path / "plugin"
    target.mkdir()

    def colliding_plugin(
        squad: SquadManifest, _roster: Roster, _runtime: object
    ) -> dict[str, bytes]:
        return {
            ".claude-plugin/plugin.json": json.dumps(
                {"name": squad_namespace(squad.squad.id)}
            ).encode(),
            ".squad/manifest.json": b"{}\n",
        }

    with pytest.raises(ExportError, match="engine-owned"):
        plan_export(
            manifest=manifest(Destination.PLUGIN, (Provider.CLAUDE,)),
            roster=roster(),
            target_root=target,
            compilers=ProviderCompilers(claude_plugin=colliding_plugin),
        )


def test_prepared_contracts_are_frozen(tmp_path: Path, compilers: ProviderCompilers) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )
    validate_prepared_export(prepared)
    with pytest.raises(FrozenInstanceError):
        prepared.receipt_path = "other.json"  # type: ignore[misc]


def test_cli_plan_and_apply_compare_saved_preview(
    tmp_path: Path, compilers: ProviderCompilers, capsys: pytest.CaptureFixture[str]
) -> None:
    target = repository(tmp_path)
    manifest_path = tmp_path / "manifest.json"
    roster_path = tmp_path / "roster.json"
    plan_path = tmp_path / "plan.json"
    manifest_path.write_text(json.dumps(manifest(Destination.PROJECT).to_dict()), encoding="utf-8")
    roster_path.write_text(json.dumps(roster().to_dict()), encoding="utf-8")
    common = [
        "--manifest",
        str(manifest_path),
        "--roster",
        str(roster_path),
        "--target",
        str(target),
        "--plan-file",
        str(plan_path),
    ]
    print_only = common[:-2]
    assert run_cli(["plan", *print_only], compilers=compilers) == 0
    assert not plan_path.exists()
    assert run_cli(["plan", *common], compilers=compilers) == 0
    plan_id = json.loads(plan_path.read_text(encoding="utf-8"))["plan_id"]
    assert run_cli(["apply", *common, "--confirm-plan-id", plan_id], compilers=compilers) == 0
    assert (target / ".squad/exports/cheeky-dportability-hdemo/export-receipt.json").exists()
    assert "plan_id" in capsys.readouterr().out


def test_cli_infers_source_root_for_canonical_squad_context(
    tmp_path: Path, compilers: ProviderCompilers
) -> None:
    target = repository(tmp_path)
    squad_dir = target / ".squad"
    squad_dir.mkdir()
    manifest_path = squad_dir / "manifest.json"
    roster_path = squad_dir / "roster.json"
    manifest_path.write_text(json.dumps(manifest(Destination.PROJECT).to_dict()), encoding="utf-8")
    roster_path.write_text(json.dumps(roster().to_dict()), encoding="utf-8")
    (squad_dir / "goal.md").write_text("# Canonical squad goal\n", encoding="utf-8")
    for role in roster().roles:
        (squad_dir / f"role-goal-{role.id}.md").write_text(
            f"# Canonical goal for {role.id}\n", encoding="utf-8"
        )
    plan_path = tmp_path / "context-plan.json"
    common = [
        "--manifest",
        str(manifest_path),
        "--roster",
        str(roster_path),
        "--target",
        str(target),
        "--plan-file",
        str(plan_path),
    ]

    assert run_cli(["plan", *common], compilers=compilers) == 0
    plan_id = json.loads(plan_path.read_text(encoding="utf-8"))["plan_id"]
    assert run_cli(["apply", *common, "--confirm-plan-id", plan_id], compilers=compilers) == 0

    context_root = target / ".squad/exports/cheeky-dportability-hdemo/context"
    assert (context_root / "squad-goal.md").read_text(encoding="utf-8") == (
        "# Canonical squad goal\n"
    )
    assert (
        json.loads((context_root / "index.json").read_text(encoding="utf-8"))["squad_goal"][
            "status"
        ]
        == "included"
    )


def test_cli_uninstall_requires_saved_exact_preview(
    tmp_path: Path, compilers: ProviderCompilers, capsys: pytest.CaptureFixture[str]
) -> None:
    target = repository(tmp_path)
    prepared = plan_export(
        manifest=manifest(Destination.PROJECT),
        roster=roster(),
        compilers=compilers,
        target_root=target,
    )
    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    plan_path = tmp_path / "uninstall-plan.json"
    common = [
        "--target",
        str(target),
        "--destination",
        Destination.PROJECT.value,
        "--squad-id",
        prepared.plan.manifest.squad.id,
        "--plan-file",
        str(plan_path),
    ]

    assert run_cli(["uninstall", *common]) == 0
    saved = json.loads(plan_path.read_text(encoding="utf-8"))
    assert saved["deletes"]
    assert run_cli(["uninstall", *common, "--confirm-plan-id", "wrong-plan"]) == 2
    assert "plan ID" in capsys.readouterr().err
    assert run_cli(["uninstall", *common, "--confirm-plan-id", saved["plan_id"]]) == 0
    assert not (target / ".squad/exports/cheeky-dportability-hdemo/export-receipt.json").exists()

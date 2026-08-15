from __future__ import annotations

import json
import os
import subprocess
import sys
import tomllib
from dataclasses import replace
from pathlib import Path

import pytest

from cheeky_squad_portability.adapters import (
    compile_claude_agents,
    compile_claude_plugin,
    compile_codex_agents,
    compile_codex_plugin,
    compile_codex_skills,
)
from cheeky_squad_portability.contracts import (
    Destination,
    EnvironmentContext,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.exporter import (
    ExportError,
    ProviderCompilers,
    apply_export,
    plan_export,
    plan_uninstall_export,
    validate_installed_export,
)
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.namespace import provider_namespace
from cheeky_squad_portability.runtime import collect_runtime_files

ROOT = Path(__file__).parents[2]
FIXTURES = ROOT / "tests" / "fixtures" / "portable"
SECRET_SENTINEL = "portable-export-secret-sentinel-4f913b"
PRIVATE_CONTEXT_PATH = "private/source-path-sentinel-8b0fae"
PRIVATE_FETCH_URL = "https://private.invalid/context?token=fetch-sentinel-0ceaf3"
PRIVATE_VERIFY_COMMAND = "verify --token verify-sentinel-c08168"
PRIVATE_INSTALL_COMMAND = "install --token install-sentinel-d909c4"
PRIVATE_MARKERS = (
    SECRET_SENTINEL,
    PRIVATE_CONTEXT_PATH,
    PRIVATE_FETCH_URL,
    PRIVATE_VERIFY_COMMAND,
    PRIVATE_INSTALL_COMMAND,
)


def _json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _manifest(destination: Destination) -> SquadManifest:
    raw = _json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    raw["destination"] = destination.value
    return SquadManifest.from_dict(raw)


def _roster(*, with_secret: bool = False) -> Roster:
    roster = load_roster(_json(FIXTURES / "roster-v2.json"))
    if not with_secret:
        return roster
    writer = roster.roles[1]
    assert writer.environment is not None
    environment = replace(
        writer.environment,
        variables=(("PORTABLE_API_TOKEN", SECRET_SENTINEL),),
        context=(
            EnvironmentContext(
                source=PRIVATE_CONTEXT_PATH,
                target="inputs/private-source",
                kind="copy",
            ),
            EnvironmentContext(
                source=PRIVATE_FETCH_URL,
                target="inputs/private-fetch",
                kind="fetch",
            ),
        ),
        tools=(
            replace(
                writer.environment.tools[0],
                verify=PRIVATE_VERIFY_COMMAND,
                install=PRIVATE_INSTALL_COMMAND,
            ),
        ),
    )
    return replace(roster, roles=(roster.roles[0], replace(writer, environment=environment)))


def _compilers() -> ProviderCompilers:
    return ProviderCompilers(
        claude_agents=compile_claude_agents,
        claude_plugin=compile_claude_plugin,
        codex_agents=compile_codex_agents,
        codex_skills=compile_codex_skills,
        codex_plugin=compile_codex_plugin,
    )


def _repository(path: Path) -> Path:
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(path)], check=True)
    return path


def _assert_stdlib_parses_without_generator(root: Path, fresh_home: Path) -> None:
    environment = {"HOME": str(fresh_home), "PATH": os.environ.get("PATH", "")}
    subprocess.run(
        [
            sys.executable,
            "-I",
            str(ROOT / "tests/python/generated_package_validator.py"),
            str(root),
        ],
        cwd=root,
        env=environment,
        check=True,
    )


def test_session_is_prompt_only_and_redacts_environment_values(tmp_path: Path) -> None:
    untouched = tmp_path / "untouched"
    untouched.mkdir()
    prepared = plan_export(
        manifest=_manifest(Destination.SESSION),
        roster=_roster(with_secret=True),
        compilers=_compilers(),
    )

    result = apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)

    assert prepared.plan.writes == prepared.plan.deletes == ()
    assert result.session_prompt is not None
    assert all(marker not in result.session_prompt for marker in PRIVATE_MARKERS)
    assert list(untouched.iterdir()) == []


def test_real_project_export_is_idempotent_and_repo_scoped(tmp_path: Path) -> None:
    target = _repository(tmp_path / "selected-project")
    outside = tmp_path / "outside.txt"
    outside.write_text("owned by user\n", encoding="utf-8")
    prepared = plan_export(
        manifest=_manifest(Destination.PROJECT),
        roster=_roster(with_secret=True),
        compilers=_compilers(),
        target_root=target,
    )

    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    validate_installed_export(
        target_root=target,
        destination=Destination.PROJECT,
        squad_id=prepared.plan.manifest.squad.id,
    )

    assert outside.read_text(encoding="utf-8") == "owned by user\n"
    assert not any(path.name.startswith(".squad-export-txn-") for path in target.iterdir())
    generated = b"".join(path.read_bytes() for path in target.rglob("*") if path.is_file())
    assert all(marker.encode() not in generated for marker in PRIVATE_MARKERS)
    again = plan_export(
        manifest=prepared.plan.manifest,
        roster=_roster(with_secret=True),
        compilers=_compilers(),
        target_root=target,
    )
    assert again.plan.writes == again.plan.deletes == ()


def test_real_user_export_requires_confirmation_and_stays_in_fake_home(
    tmp_path: Path,
) -> None:
    fake_home = tmp_path / "fresh-home"
    fake_home.mkdir()
    prepared = plan_export(
        manifest=_manifest(Destination.USER),
        roster=_roster(),
        compilers=_compilers(),
        target_root=fake_home,
        home=fake_home,
    )

    with pytest.raises(ExportError, match="global-write confirmation"):
        apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    apply_export(
        prepared,
        confirmed_plan_id=prepared.plan.plan_id,
        global_write_confirmed=True,
    )
    report = validate_installed_export(
        target_root=fake_home,
        home=fake_home,
        destination=Destination.USER,
        squad_id=prepared.plan.manifest.squad.id,
    )

    assert report.checked_files
    assert all(path.resolve().is_relative_to(fake_home) for path in fake_home.rglob("*"))


def test_real_plugin_is_vendored_and_never_installed(tmp_path: Path) -> None:
    target = tmp_path / "portable-plugin"
    target.mkdir()
    fresh_home = tmp_path / "unused-home"
    fresh_home.mkdir()
    runtime = collect_runtime_files(ROOT)
    prepared = plan_export(
        manifest=_manifest(Destination.PLUGIN),
        roster=_roster(),
        compilers=_compilers(),
        target_root=target,
        home=fresh_home,
        vendored_files=runtime,
        executable_paths={path for path in runtime if path.endswith(".sh")},
        license_bytes=runtime["LICENSE"],
    )

    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)
    validate_installed_export(
        target_root=target,
        destination=Destination.PLUGIN,
        squad_id=prepared.plan.manifest.squad.id,
        home=fresh_home,
    )
    _assert_stdlib_parses_without_generator(target, fresh_home)

    assert (target / ".claude-plugin/plugin.json").is_file()
    assert (target / ".codex-plugin/plugin.json").is_file()
    namespace = provider_namespace(prepared.plan.manifest.squad.id)
    command_copies = {
        target / "commands/squad-workflow.md",
        target / "runtime/commands/squad-workflow.md",
        target / f"plugins/{namespace}/runtime/commands/squad-workflow.md",
        target / "shared/runtime/commands/squad-workflow.md",
    }
    assert all(path.is_file() for path in command_copies)
    assert {path.read_bytes() for path in command_copies} == {
        (ROOT / "commands/squad-workflow.md").read_bytes()
    }
    assert list(fresh_home.iterdir()) == []
    assert not any(
        b"cheeky_squad_portability" in path.read_bytes()
        for path in target.rglob("*")
        if path.is_file() and path.suffix in {".py", ".sh"}
    )


def test_plugin_redacts_private_provisioning_and_snapshots_only_authored_context(
    tmp_path: Path,
) -> None:
    source_root = tmp_path / "source"
    authored = source_root / ".squad"
    authored.mkdir(parents=True)
    bodies = {
        "goal.md": "# Squad goal\n\nsquad-body-sentinel-35f71d\n",
        "role-goal-evidence-reader.md": ("# Evidence reader goal\n\nreader-body-sentinel-e7cc91\n"),
        "role-goal-report-writer.md": ("# Report writer goal\n\nwriter-body-sentinel-aed40d\n"),
    }
    for name, body in bodies.items():
        (authored / name).write_text(body, encoding="utf-8")

    target = tmp_path / "portable-private-plugin"
    target.mkdir()
    runtime = collect_runtime_files(ROOT)
    prepared = plan_export(
        manifest=_manifest(Destination.PLUGIN),
        roster=_roster(with_secret=True),
        compilers=_compilers(),
        target_root=target,
        source_root=source_root,
        vendored_files=runtime,
        executable_paths={path for path in runtime if path.endswith(".sh")},
        license_bytes=runtime["LICENSE"],
    )

    apply_export(prepared, confirmed_plan_id=prepared.plan.plan_id)

    generated = {
        path.relative_to(target).as_posix(): path.read_bytes()
        for path in target.rglob("*")
        if path.is_file()
    }
    combined = b"\n".join(generated.values())
    for marker in PRIVATE_MARKERS:
        assert marker.encode() not in combined

    portable_roster = json.loads(generated["shared/roster.json"])
    writer_environment = portable_roster["roles"][1]["environment"]
    assert writer_environment["variables"] == {"PORTABLE_API_TOKEN": ""}
    assert writer_environment["context"] == []
    assert writer_environment["tools"] == [{"kind": "system", "name": "jq"}]

    expected_context = {
        ".squad/context/squad-goal.md": bodies["goal.md"].encode(),
        ".squad/context/roles/evidence-reader.md": bodies["role-goal-evidence-reader.md"].encode(),
        ".squad/context/roles/report-writer.md": bodies["role-goal-report-writer.md"].encode(),
    }
    for expected_path, body in expected_context.items():
        assert generated[expected_path] == body
        sentinel = body.decode().splitlines()[-1].encode()
        assert [path for path, content in generated.items() if sentinel in content] == [
            expected_path
        ]

    context_index = json.loads(generated[".squad/context/index.json"])
    assert context_index["squad_goal"]["source"] == ".squad/goal.md"
    assert [item["source"] for item in context_index["role_goals"]] == [
        ".squad/role-goal-evidence-reader.md",
        ".squad/role-goal-report-writer.md",
    ]


def test_malformed_receipt_blocks_plan_and_uninstall(tmp_path: Path) -> None:
    target = _repository(tmp_path / "project")
    receipt = target / ".squad/exports/cheeky-dportability-hdemo/export-receipt.json"
    receipt.parent.mkdir(parents=True)
    receipt.write_text("not-json", encoding="utf-8")
    manifest = _manifest(Destination.PROJECT)

    with pytest.raises(ExportError, match="receipt is invalid"):
        plan_export(
            manifest=manifest,
            roster=_roster(),
            compilers=_compilers(),
            target_root=target,
        )
    with pytest.raises(ExportError, match="receipt is invalid"):
        plan_uninstall_export(
            target_root=target,
            destination=Destination.PROJECT,
            squad_id=manifest.squad.id,
        )


def test_release_versions_match_portable_goldens() -> None:
    package = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    version = package["project"]["version"]
    manifest = _json(FIXTURES / "manifest-v2.json")
    assert isinstance(manifest, dict)

    assert version == manifest["export_version"] == "1.2.0"
    for path in (
        ROOT / "tests/fixtures/providers/claude/plugin.json",
        ROOT / "tests/fixtures/providers/codex/plugin/.codex-plugin/plugin.json",
    ):
        value = _json(path)
        assert isinstance(value, dict)
        assert value["version"] == version

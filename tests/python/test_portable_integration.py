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
from cheeky_squad_portability.contracts import Destination, Roster, SquadManifest
from cheeky_squad_portability.exporter import (
    ExportError,
    ProviderCompilers,
    apply_export,
    plan_export,
    uninstall_export,
    validate_installed_export,
)
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.runtime import collect_runtime_files

ROOT = Path(__file__).parents[2]
FIXTURES = ROOT / "tests" / "fixtures" / "portable"
SECRET_SENTINEL = "portable-export-secret-sentinel-4f913b"


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
    (path / ".git").mkdir()
    return path


def _assert_stdlib_parses_without_generator(root: Path, fresh_home: Path) -> None:
    script = """
import json
import pathlib
import tomllib

for path in pathlib.Path('.').rglob('*'):
    if not path.is_file():
        continue
    if path.suffix == '.json':
        json.loads(path.read_text(encoding='utf-8'))
    elif path.suffix == '.toml':
        tomllib.loads(path.read_text(encoding='utf-8'))
"""
    environment = {"HOME": str(fresh_home), "PATH": os.environ.get("PATH", "")}
    subprocess.run(
        [sys.executable, "-I", "-c", script],
        cwd=root,
        env=environment,
        check=True,
    )
    for script_path in root.rglob("*.sh"):
        subprocess.run(
            ["bash", "-n", str(script_path)],
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
    assert SECRET_SENTINEL not in result.session_prompt
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
    assert SECRET_SENTINEL.encode() not in b"".join(
        path.read_bytes() for path in target.rglob("*") if path.is_file()
    )
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
    assert list(fresh_home.iterdir()) == []
    assert not any(
        b"cheeky_squad_portability" in path.read_bytes()
        for path in target.rglob("*")
        if path.is_file() and path.suffix in {".py", ".sh"}
    )


def test_malformed_receipt_blocks_plan_and_uninstall(tmp_path: Path) -> None:
    target = _repository(tmp_path / "project")
    receipt = target / ".squad/export-receipt.json"
    receipt.parent.mkdir()
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
        uninstall_export(
            target_root=target,
            destination=Destination.PROJECT,
            squad_id=manifest.squad.id,
            confirmed=True,
        )


def test_release_versions_match_portable_goldens() -> None:
    package = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    version = package["project"]["version"]
    manifest = _json(FIXTURES / "manifest-v2.json")
    assert isinstance(manifest, dict)

    assert version == manifest["export_version"] == "1.1.0"
    for path in (
        ROOT / "tests/fixtures/providers/claude/plugin.json",
        ROOT / "tests/fixtures/providers/codex/plugin/.codex-plugin/plugin.json",
    ):
        value = _json(path)
        assert isinstance(value, dict)
        assert value["version"] == version

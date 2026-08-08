from __future__ import annotations

import json
import tomllib
from pathlib import Path

from cheeky_squad_portability.adapters import (
    compile_claude_agents,
    compile_claude_plugin,
    compile_codex_agents,
    compile_codex_plugin,
)
from cheeky_squad_portability.contracts import Roster, SquadManifest
from cheeky_squad_portability.runtime import collect_runtime_files

ROOT = Path(__file__).parents[2]
PORTABLE = ROOT / "tests" / "fixtures" / "portable"


def _json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def test_both_providers_compile_the_same_active_roles() -> None:
    manifest = SquadManifest.from_dict(_json(PORTABLE / "manifest-v2.json"))
    roster = Roster.from_dict(_json(PORTABLE / "roster-v2.json"))

    claude = compile_claude_agents(manifest, roster)
    codex = compile_codex_agents(manifest, roster)

    claude_ids = {Path(path).stem for path in claude}
    codex_ids = {tomllib.loads(content.decode("utf-8"))["name"] for content in codex.values()}
    assert (
        claude_ids
        == codex_ids
        == {
            "cheeky-portability-demo--evidence-reader",
            "cheeky-portability-demo--report-writer",
        }
    )


def test_both_standalone_packages_vendor_the_required_runtime() -> None:
    manifest = SquadManifest.from_dict(_json(PORTABLE / "manifest-v2.json"))
    roster = Roster.from_dict(_json(PORTABLE / "roster-v2.json"))
    runtime = collect_runtime_files(ROOT)

    claude = compile_claude_plugin(manifest, roster, runtime)
    codex = compile_codex_plugin(manifest, roster, runtime)

    assert ".claude-plugin/plugin.json" in claude
    assert ".codex-plugin/plugin.json" in codex
    assert claude["LICENSE"] == runtime["LICENSE"]
    assert codex["runtime/LICENSE"] == runtime["LICENSE"]
    assert "hooks" in json.loads(claude[".claude-plugin/plugin.json"])
    assert b"mutating role sequentially" in next(
        content for path, content in codex.items() if path.endswith("--dispatch/SKILL.md")
    )

from __future__ import annotations

import copy
import json
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest
from jsonschema.validators import validator_for
from referencing import Registry, Resource

from cheeky_squad_portability import (
    ContractError,
    Destination,
    Roster,
    SquadManifest,
    build_export_plan,
    load_roster,
    migrate_legacy_roster,
)

ROOT = Path(__file__).parents[2]
FIXTURES = ROOT / "tests" / "fixtures" / "portable"
SCHEMAS = ROOT / "schemas"


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def schema_registry() -> Registry:
    resources = []
    for path in sorted(SCHEMAS.glob("*.schema.json")):
        contents = load_json(path)
        assert isinstance(contents, dict)
        resources.append((contents["$id"], Resource.from_contents(contents)))
    return Registry().with_resources(resources)


@pytest.mark.parametrize(
    ("schema_name", "fixture_name"),
    [("manifest.schema.json", "manifest-v2.json"), ("roster.schema.json", "roster-v2.json")],
)
def test_canonical_fixtures_validate(schema_name: str, fixture_name: str) -> None:
    schema = load_json(SCHEMAS / schema_name)
    validator = validator_for(schema)(schema, registry=schema_registry())
    validator.validate(load_json(FIXTURES / fixture_name))


def test_legacy_migration_is_pure_and_matches_golden() -> None:
    legacy = load_json(FIXTURES / "legacy-roster.json")
    original = copy.deepcopy(legacy)

    migrated = migrate_legacy_roster(legacy)

    assert legacy == original
    assert migrated.to_dict() == load_json(FIXTURES / "roster-v2.json")
    assert load_roster(migrated.to_dict()) == migrated


def test_current_seed_template_remains_migratable() -> None:
    migrated = load_roster(load_json(ROOT / "templates" / "roster.json"))

    assert isinstance(migrated, Roster)
    assert migrated.roles[0].id == "example-role-delete-me"
    assert migrated.roles[0].active is False


def test_contracts_are_frozen() -> None:
    manifest = SquadManifest.from_dict(load_json(FIXTURES / "manifest-v2.json"))

    with pytest.raises(FrozenInstanceError):
        manifest.destination = Destination.USER  # type: ignore[misc]


def test_cadence_and_destination_are_independent() -> None:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    raw["destination"] = "plugin"

    manifest = SquadManifest.from_dict(raw)

    assert manifest.execution_mode.value == "one-time"
    assert manifest.destination is Destination.PLUGIN


def test_export_plan_is_content_addressed_and_schema_valid() -> None:
    manifest = SquadManifest.from_dict(load_json(FIXTURES / "manifest-v2.json"))
    arguments = {
        "manifest": manifest,
        "target_root": "/tmp/export-target",
        "source_sha256": "a" * 64,
        "writes": {"z.txt": b"z", "a.txt": b"alpha"},
        "deletes": ["old.txt"],
        "executable_paths": [],
    }

    first = build_export_plan(**arguments)
    second = build_export_plan(**arguments)

    assert first == second
    assert first.plan_id == second.plan_id
    assert [item["path"] for item in first.to_dict()["writes"]] == ["a.txt", "z.txt"]
    schema = load_json(SCHEMAS / "export-plan.schema.json")
    validator_for(schema)(schema, registry=schema_registry()).validate(first.to_dict())


@pytest.mark.parametrize("path", ["../escape", "/absolute", "nested/../../escape"])
def test_export_plan_rejects_unsafe_paths(path: str) -> None:
    manifest = SquadManifest.from_dict(load_json(FIXTURES / "manifest-v2.json"))

    with pytest.raises(ContractError, match="relative path without traversal"):
        build_export_plan(
            manifest=manifest,
            target_root="/tmp/export-target",
            source_sha256="a" * 64,
            writes={path: b"unsafe"},
        )


def test_export_plan_rejects_invalid_source_digest() -> None:
    manifest = SquadManifest.from_dict(load_json(FIXTURES / "manifest-v2.json"))

    with pytest.raises(ContractError, match="lowercase SHA-256"):
        build_export_plan(
            manifest=manifest,
            target_root="/tmp/export-target",
            source_sha256="z" * 64,
            writes={},
        )


def test_runtime_owner_must_be_selected() -> None:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    raw["providers"] = ["codex"]

    with pytest.raises(ContractError, match="runtime_owner"):
        SquadManifest.from_dict(raw)

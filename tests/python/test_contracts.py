from __future__ import annotations

import copy
import json
from dataclasses import FrozenInstanceError, replace
from pathlib import Path

import pytest
from jsonschema.validators import validator_for
from referencing import Registry, Resource

from cheeky_squad_portability import (
    MAX_ACTIVE_ROLES,
    ContractError,
    Destination,
    EnvironmentContext,
    OnboardedSkill,
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
    # roster-v2.json carries one v2-only field (onboarded_skills on report-writer)
    # that the legacy schema has no way to express, so migration can never
    # produce it; everything else must still match the canonical fixture exactly.
    golden = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(golden, dict)
    golden_roles = golden["roles"]
    assert isinstance(golden_roles, list) and isinstance(golden_roles[1], dict)
    golden_roles[1].pop("onboarded_skills")
    assert migrated.to_dict() == golden
    assert load_roster(migrated.to_dict()) == migrated


@pytest.mark.parametrize("schema_version", [1, 3, "1", "2", "3"])
def test_present_unsupported_roster_schema_never_uses_legacy_migration(
    schema_version: object,
) -> None:
    roster = load_json(FIXTURES / "legacy-roster.json")
    assert isinstance(roster, dict)
    roster["schema_version"] = schema_version

    with pytest.raises(ContractError, match="schema_version is unsupported"):
        load_roster(roster)


def test_current_seed_template_is_canonical_v2() -> None:
    raw = load_json(ROOT / "templates" / "roster.json")
    assert isinstance(raw, dict)
    assert raw["schema_version"] == 2
    validator_for(load_json(SCHEMAS / "roster.schema.json"))(
        load_json(SCHEMAS / "roster.schema.json"), registry=schema_registry()
    ).validate(raw)

    migrated = load_roster(raw)

    assert isinstance(migrated, Roster)
    assert migrated.roles[0].id == "example-role-delete-me"
    assert migrated.roles[0].active is False


@pytest.mark.parametrize("source", ["inputs/*.md", "inputs/file?.md", "inputs/[ab].md"])
def test_local_environment_context_rejects_glob_sources(source: str) -> None:
    with pytest.raises(ContractError, match="without globs"):
        EnvironmentContext(source=source, target="inputs", kind="copy")

    raw = load_json(ROOT / "templates" / "roster.json")
    assert isinstance(raw, dict)
    raw["roles"][0]["environment"]["context"][0]["source"] = source  # type: ignore[index]
    schema = load_json(SCHEMAS / "roster.schema.json")
    validator = validator_for(schema)(schema, registry=schema_registry())
    assert list(validator.iter_errors(raw))


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

    schema = load_json(SCHEMAS / "manifest.schema.json")
    errors = list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(raw))
    assert errors


@pytest.mark.parametrize("squad_id", ["foo..bar", "-leading", "trailing-"])
def test_manifest_schema_and_runtime_reject_the_same_invalid_squad_ids(
    squad_id: str,
) -> None:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    assert isinstance(raw["squad"], dict)
    raw["squad"]["id"] = squad_id
    schema = load_json(SCHEMAS / "manifest.schema.json")

    assert list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(raw))
    with pytest.raises(ContractError, match=r"squad\.id"):
        SquadManifest.from_dict(raw)


def test_manifest_schema_and_runtime_accept_full_semver() -> None:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    raw["export_version"] = "1.2.3-alpha.1+build.7"
    schema = load_json(SCHEMAS / "manifest.schema.json")

    validator_for(schema)(schema, registry=schema_registry()).validate(raw)
    assert SquadManifest.from_dict(raw).export_version == "1.2.3-alpha.1+build.7"


def test_manifest_schema_and_runtime_enforce_squad_id_length() -> None:
    raw = load_json(FIXTURES / "manifest-v2.json")
    assert isinstance(raw, dict)
    assert isinstance(raw["squad"], dict)
    raw["squad"]["id"] = "a" * 64
    schema = load_json(SCHEMAS / "manifest.schema.json")

    assert list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(raw))
    with pytest.raises(ContractError, match="at most 63"):
        SquadManifest.from_dict(raw)


def test_export_plan_schema_rejects_traversal_paths() -> None:
    manifest = SquadManifest.from_dict(load_json(FIXTURES / "manifest-v2.json"))
    plan = build_export_plan(
        manifest=manifest,
        target_root="/tmp/export-target",
        source_sha256="a" * 64,
        writes={"safe.txt": b"safe"},
    ).to_dict()
    assert isinstance(plan["writes"], list)
    assert isinstance(plan["writes"][0], dict)
    plan["writes"][0]["path"] = "../escape"
    schema = load_json(SCHEMAS / "export-plan.schema.json")

    assert list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(plan))


@pytest.mark.parametrize(
    "unsafe",
    ["../escape/**", "/absolute/**", "nested/../escape/**", "a/", "a//b"],
)
def test_roster_schema_and_runtime_reject_unsafe_ownership_paths(unsafe: str) -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[0], dict)
    ownership = roles[0]["file_ownership"]
    assert isinstance(ownership, dict)
    ownership["include"] = [unsafe]
    schema = load_json(SCHEMAS / "roster.schema.json")

    assert list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(raw))
    with pytest.raises(ContractError, match="project-relative path"):
        Roster.from_dict(raw)


@pytest.mark.parametrize("key", ["BAD-NAME", "1STARTS_WITH_NUMBER", "HAS.DOT"])
def test_roster_schema_and_runtime_reject_invalid_environment_variable_names(
    key: str,
) -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[1], dict)
    environment = roles[1]["environment"]
    assert isinstance(environment, dict)
    environment["variables"] = {key: "value"}
    schema = load_json(SCHEMAS / "roster.schema.json")

    assert list(validator_for(schema)(schema, registry=schema_registry()).iter_errors(raw))
    with pytest.raises(ContractError, match="shell identifiers"):
        Roster.from_dict(raw)


@pytest.mark.parametrize(
    ("field", "unsafe"),
    [
        ("goal_ref", "../role-goal.md"),
        ("agent_file", "/tmp/agent.md"),
        ("workspace", ".squad/workspaces/../escape"),
    ],
)
def test_roster_rejects_unsafe_path_bearing_fields(field: str, unsafe: str) -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[1], dict)
    role = roles[1]
    if field == "agent_file":
        overrides = role["provider_overrides"]
        assert isinstance(overrides, dict) and isinstance(overrides["claude"], dict)
        overrides["claude"][field] = unsafe
    elif field == "workspace":
        environment = role["environment"]
        assert isinstance(environment, dict)
        environment[field] = unsafe
    else:
        role[field] = unsafe

    with pytest.raises(ContractError, match="project-relative path"):
        Roster.from_dict(raw)


def test_claude_worktree_isolation_round_trips_and_legacy_migrates() -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[0], dict)
    overrides = roles[0]["provider_overrides"]
    assert isinstance(overrides, dict) and isinstance(overrides["claude"], dict)
    overrides["claude"]["isolation"] = "worktree"

    canonical = Roster.from_dict(raw)
    assert canonical.roles[0].provider_overrides is not None
    assert canonical.roles[0].provider_overrides.claude is not None
    assert canonical.roles[0].provider_overrides.claude.isolation == "worktree"
    assert canonical.to_dict() == raw

    legacy = load_json(FIXTURES / "legacy-roster.json")
    assert isinstance(legacy, dict)
    legacy_roles = legacy["roles"]
    assert isinstance(legacy_roles, list) and isinstance(legacy_roles[0], dict)
    legacy_roles[0]["isolation"] = "worktree"
    migrated = migrate_legacy_roster(legacy)
    assert migrated.roles[0].provider_overrides is not None
    assert migrated.roles[0].provider_overrides.claude is not None
    assert migrated.roles[0].provider_overrides.claude.isolation == "worktree"


def test_claude_override_rejects_unknown_isolation() -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[0], dict)
    overrides = roles[0]["provider_overrides"]
    assert isinstance(overrides, dict) and isinstance(overrides["claude"], dict)
    overrides["claude"]["isolation"] = "container"

    with pytest.raises(ContractError, match="isolation must be worktree"):
        Roster.from_dict(raw)


def test_onboarded_skill_round_trips_from_the_canonical_fixture() -> None:
    roster = Roster.from_dict(load_json(FIXTURES / "roster-v2.json"))

    writer = next(role for role in roster.roles if role.id == "report-writer")
    assert writer.onboarded_skills == (
        OnboardedSkill(
            name="citation-formatter",
            local_path=".squad/skills/report-writer/citation-formatter/SKILL.md",
            purpose="Format citations consistently in the final report",
            approval_mode="user",
            kind="knowledge",
            source_url="https://github.com/anthropics/skills",
            approved_at="2026-08-08T00:00:03Z",
        ),
        OnboardedSkill(
            name="docx-export-cli",
            local_path=".squad/skills/report-writer/docx-export-cli/SKILL.md",
            purpose="Operate the export CLI to convert the markdown report to signed-off DOCX",
            approval_mode="auto",
            kind="execution",
            source_url="https://github.com/addyosmani/agent-skills",
        ),
    )
    reader = next(role for role in roster.roles if role.id == "evidence-reader")
    assert reader.onboarded_skills == ()
    assert "onboarded_skills" not in reader.to_dict()


def test_onboarded_skill_defaults_kind_to_knowledge_and_serializes_it_always() -> None:
    skill = OnboardedSkill(
        name="original-skill",
        local_path=".squad/skills/report-writer/original-skill/SKILL.md",
        purpose="An original skill authored for this squad",
        approval_mode="auto",
    )

    assert skill.kind == "knowledge"
    assert skill.to_dict() == {
        "name": "original-skill",
        "local_path": ".squad/skills/report-writer/original-skill/SKILL.md",
        "purpose": "An original skill authored for this squad",
        "approval_mode": "auto",
        "kind": "knowledge",
    }


def test_onboarded_skill_from_dict_defaults_kind_for_backward_compatibility() -> None:
    skill = OnboardedSkill.from_dict(
        {
            "name": "original-skill",
            "local_path": ".squad/skills/report-writer/original-skill/SKILL.md",
            "purpose": "An original skill authored for this squad",
            "approval_mode": "auto",
        },
        "onboarded_skills[0]",
    )

    assert skill.kind == "knowledge"


def test_onboarded_skill_rejects_bad_kind() -> None:
    with pytest.raises(ContractError, match="kind must be knowledge or execution"):
        OnboardedSkill(
            name="a-skill",
            local_path=".squad/skills/role/skill/SKILL.md",
            purpose="purpose",
            approval_mode="user",
            kind="logic",
        )


def test_onboarded_skill_rejects_bad_name_and_approval_mode() -> None:
    with pytest.raises(ContractError, match="lowercase kebab-case"):
        OnboardedSkill(
            name="Not_Kebab",
            local_path=".squad/skills/role/skill/SKILL.md",
            purpose="purpose",
            approval_mode="user",
        )
    with pytest.raises(ContractError, match="approval_mode must be user or auto"):
        OnboardedSkill(
            name="a-skill",
            local_path=".squad/skills/role/skill/SKILL.md",
            purpose="purpose",
            approval_mode="maybe",
        )


def test_role_rejects_duplicate_onboarded_skill_names() -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[1], dict)
    onboarded = roles[1]["onboarded_skills"]
    assert isinstance(onboarded, list) and isinstance(onboarded[0], dict)
    onboarded.append(dict(onboarded[0]))

    with pytest.raises(ContractError, match="onboarded_skills must have unique names"):
        Roster.from_dict(raw)


def test_role_rejects_unknown_onboarded_skill_field() -> None:
    raw = load_json(FIXTURES / "roster-v2.json")
    assert isinstance(raw, dict)
    roles = raw["roles"]
    assert isinstance(roles, list) and isinstance(roles[1], dict)
    onboarded = roles[1]["onboarded_skills"]
    assert isinstance(onboarded, list) and isinstance(onboarded[0], dict)
    onboarded[0]["unexpected"] = "nope"

    with pytest.raises(ContractError, match="unknown fields"):
        Roster.from_dict(raw)


def test_legacy_migration_yields_no_onboarded_skills_key() -> None:
    legacy = load_json(FIXTURES / "legacy-roster.json")
    migrated = migrate_legacy_roster(legacy)

    assert all(role.onboarded_skills == () for role in migrated.roles)
    assert all("onboarded_skills" not in role.to_dict() for role in migrated.roles)


def test_max_active_roles_and_active_roles_helper_grandfather_over_cap_rosters() -> None:
    assert MAX_ACTIVE_ROLES == 5

    roster = Roster.from_dict(load_json(FIXTURES / "roster-v2.json"))
    assert roster.active_roles() == tuple(role for role in roster.roles if role.active)

    template_role = roster.roles[0]
    over_cap_roles = tuple(
        replace(template_role, id=f"{template_role.id}-{index}", onboarded_skills=())
        for index in range(MAX_ACTIVE_ROLES + 1)
    )
    over_cap = Roster(
        squad_goal_ref=roster.squad_goal_ref,
        execution_mode=roster.execution_mode,
        roles=over_cap_roles,
    )

    assert len(over_cap.active_roles()) == MAX_ACTIVE_ROLES + 1

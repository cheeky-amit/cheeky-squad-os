"""Deterministic Codex compiler for portable squad snapshots.

The adapter only renders bytes. Destination-specific code decides whether those
bytes belong under a project's ``.codex``/``.agents`` directories or the
equivalent user directories.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import PurePosixPath

from cheeky_squad_portability.contracts import (
    Capability,
    CodexOverride,
    Destination,
    Provider,
    ReasoningEffort,
    ReasoningProfile,
    Role,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.json_io import pretty_json
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.namespace import (
    provider_dispatch_skill_id,
    provider_namespace,
    provider_role_id,
    provider_role_skill_id,
)
from cheeky_squad_portability.runtime import is_private_runtime_path

_MUTATING_CAPABILITIES = frozenset(
    {
        Capability.FILESYSTEM_EDIT.value,
        Capability.FILESYSTEM_WRITE.value,
        Capability.NOTEBOOK_EDIT.value,
        Capability.SHELL_EXECUTE.value,
    }
)
_PROFILE_EFFORT = {
    ReasoningProfile.FAST: ReasoningEffort.LOW,
    ReasoningProfile.BALANCED: ReasoningEffort.MEDIUM,
    ReasoningProfile.DEEP: ReasoningEffort.HIGH,
    ReasoningProfile.INHERIT: ReasoningEffort.INHERIT,
}


def codex_role_id(manifest: SquadManifest, role: Role) -> str:
    """Return a stable, namespaced identifier accepted by Codex discovery."""

    return provider_role_id(manifest.squad.id, role.id)


def compile_codex_agents(manifest: SquadManifest, roster: Roster | object) -> dict[str, bytes]:
    """Compile active roles to destination-neutral Codex agent TOML files."""

    canonical = _canonical_roster(manifest, roster)
    return {
        f"agents/{codex_role_id(manifest, role)}.toml": _agent_toml(manifest, role)
        for role in _active_roles(canonical)
    }


def compile_codex_skills(manifest: SquadManifest, roster: Roster | object) -> dict[str, bytes]:
    """Compile prompt-baked role skills for project or user skill discovery."""

    canonical = _canonical_roster(manifest, roster)
    return {
        f"skills/{provider_role_skill_id(manifest.squad.id, role.id)}/SKILL.md": (
            _role_skill(manifest, role)
        )
        for role in _active_roles(canonical)
    }


def compile_codex_plugin(
    manifest: SquadManifest,
    roster: Roster | object,
    runtime_files: Mapping[str, bytes],
) -> dict[str, bytes]:
    """Compile a standalone Codex plugin with prompt-baked role dispatch.

    Codex plugins do not directly package custom-agent discovery. Consequently
    this output intentionally contains no ``agents/*.toml`` files: packaged
    skills carry the role instructions, and the dispatch skill runs mutating
    roles sequentially.
    """

    canonical = _canonical_roster(manifest, roster)
    roles = _active_roles(canonical)
    plugin_name = provider_namespace(manifest.squad.id)
    mutating = any(_is_mutating(role) for role in roles)
    source_description = manifest.squad.description or (
        f"Portable Codex squad snapshot for {manifest.squad.name}"
    )
    description = _bounded_text(source_description, 512)
    plugin_manifest = {
        "author": {"name": "cheeky-squad-os export"},
        "description": description,
        "interface": {
            "capabilities": ["Interactive", "Read", *(["Write"] if mutating else [])],
            "category": "Productivity",
            "defaultPrompt": [
                _bounded_text(f"Dispatch the packaged {manifest.squad.name} squad", 128)
            ],
            "developerName": "cheeky-squad-os",
            "displayName": _bounded_text(manifest.squad.name, 64),
            "longDescription": _bounded_text(source_description, 1024),
            "shortDescription": _bounded_text(description, 96),
        },
        "keywords": ["squad", "portable-agents", "prompt-baked-roles"],
        "license": "MIT",
        "name": plugin_name,
        "skills": "./skills/",
        "version": manifest.export_version,
    }
    marketplace = {
        "interface": {"displayName": _bounded_text(f"{manifest.squad.name} portable squad", 64)},
        "name": plugin_name,
        "plugins": [
            {
                "category": "Productivity",
                "name": plugin_name,
                "policy": {
                    "authentication": "ON_INSTALL",
                    "installation": "AVAILABLE",
                },
                "source": {
                    "path": f"./plugins/{plugin_name}",
                    "source": "local",
                },
            }
        ],
    }
    if "LICENSE" not in runtime_files:
        raise ContractError("a self-contained Codex plugin requires LICENSE in runtime_files")
    plugin_files: dict[str, bytes] = {
        ".codex-plugin/plugin.json": pretty_json(plugin_manifest).encode("utf-8"),
        "LICENSE": runtime_files["LICENSE"],
        f"skills/{provider_dispatch_skill_id(manifest.squad.id)}/SKILL.md": (
            _dispatch_skill(manifest, roles)
        ),
    }
    plugin_files.update(compile_codex_skills(manifest, canonical))
    plugin_files.update(
        {
            f"roles/{codex_role_id(manifest, role)}.md": _role_prompt(manifest, role)
            for role in roles
        }
    )
    for path, content in sorted(runtime_files.items()):
        _validate_runtime_path(path)
        if is_private_runtime_path(PurePosixPath(path)):
            raise ContractError(f"runtime file path {path!r} is private or live state")
        if not isinstance(content, bytes):
            raise ContractError(f"runtime_files[{path!r}] must be bytes")
        if path == "LICENSE":
            continue
        plugin_files[f"runtime/{path}"] = content
    output: dict[str, bytes] = {
        ".agents/plugins/marketplace.json": pretty_json(marketplace).encode("utf-8"),
        **plugin_files,
    }
    output.update(
        {f"plugins/{plugin_name}/{path}": content for path, content in plugin_files.items()}
    )
    return dict(sorted(output.items()))


def _canonical_roster(manifest: SquadManifest, roster: Roster | object) -> Roster:
    if Provider.CODEX not in manifest.providers:
        raise ContractError("manifest.providers must select codex for Codex compilation")
    canonical = roster if isinstance(roster, Roster) else load_roster(roster)
    if manifest.execution_mode is not canonical.execution_mode:
        raise ContractError("manifest and roster execution modes must match")
    return canonical


def _active_roles(roster: Roster) -> tuple[Role, ...]:
    return tuple(sorted((role for role in roster.roles if role.active), key=lambda role: role.id))


def _is_mutating(role: Role) -> bool:
    return bool(_MUTATING_CAPABILITIES.intersection(role.capabilities))


def _codex_override(role: Role) -> CodexOverride | None:
    if role.provider_overrides is None:
        return None
    return role.provider_overrides.codex


def _sandbox_mode(role: Role) -> str:
    override = _codex_override(role)
    requested = None if override is None else override.sandbox_mode
    if _is_mutating(role):
        if requested is not None and requested != "workspace-write":
            raise ContractError(
                f"mutating role {role.id!r} must use Codex sandbox_mode workspace-write"
            )
        return "workspace-write"
    if requested is not None and requested != "read-only":
        raise ContractError(f"read-only role {role.id!r} must use Codex sandbox_mode read-only")
    return "read-only"


def _reasoning_effort(role: Role) -> ReasoningEffort:
    override = _codex_override(role)
    if override is not None and override.reasoning_effort is not None:
        return override.reasoning_effort
    if role.reasoning.effort is not ReasoningEffort.INHERIT:
        return role.reasoning.effort
    return _PROFILE_EFFORT[role.reasoning.profile]


def _agent_toml(manifest: SquadManifest, role: Role) -> bytes:
    override = _codex_override(role)
    lines = [
        f"name = {_toml_string(codex_role_id(manifest, role))}",
        f"description = {_toml_string(role.description)}",
        f"developer_instructions = {_toml_string(_developer_instructions(manifest, role))}",
    ]
    if override is not None and override.model is not None:
        lines.append(f"model = {_toml_string(override.model)}")
    effort = _reasoning_effort(role)
    if effort is not ReasoningEffort.INHERIT:
        lines.append(f"model_reasoning_effort = {_toml_string(effort.value)}")
    lines.append(f"sandbox_mode = {_toml_string(_sandbox_mode(role))}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _developer_instructions(manifest: SquadManifest, role: Role) -> str:
    lines = [
        f"You are the {role.id} role in the {manifest.squad.name} squad.",
        f"Purpose: {role.purpose}",
        f"Execution cadence: {manifest.execution_mode.value}.",
        *_role_context_instructions(manifest, role),
        "Requested capabilities: " + ", ".join(sorted(role.capabilities)) + ".",
        "File ownership is an instructional coordination boundary in Codex v1; "
        "it is not mechanically enforced.",
        "Work only within these instructed paths: " + ", ".join(role.file_ownership.include) + ".",
    ]
    if role.file_ownership.exclude:
        lines.append("Do not modify these paths: " + ", ".join(role.file_ownership.exclude) + ".")
    if role.environment is not None:
        lines.extend(_environment_instructions(role))
    if role.onboarded_skills:
        lines.extend(_onboarded_skills_instructions(role))
    if _is_mutating(role):
        lines.append(
            "This role mutates the workspace. Dispatch it sequentially; do not run it "
            "concurrently with another mutating squad role."
        )
    else:
        lines.append("This role is read-only and may run concurrently with other read-only roles.")
    lines.append(
        "Capabilities and ownership remain subject to the active Codex sandbox and tool policy."
    )
    return "\n".join(lines)


def _environment_instructions(role: Role) -> list[str]:
    assert role.environment is not None
    environment = role.environment
    lines = [f"Workspace hint: {environment.workspace}"]
    if environment.directories:
        lines.append("Expected workspace directories: " + ", ".join(environment.directories) + ".")
    if environment.variables:
        variables = ", ".join(key for key, _ in environment.variables)
        lines.append(
            f"Expected environment variable names: {variables}. "
            "Values are intentionally not embedded."
        )
    if environment.context:
        context = ", ".join(
            f"{item.source} -> {item.target} ({item.kind})" for item in environment.context
        )
        lines.append(f"Expected context material: {context}.")
    if environment.tools:
        rendered_tools = [f"{tool.name} ({tool.kind})" for tool in environment.tools]
        tools = ", ".join(rendered_tools)
        lines.append(f"Expected tools: {tools}.")
    return lines


def _onboarded_skills_instructions(role: Role) -> list[str]:
    lines = ["Onboarded skills for this role:"]
    for skill in role.onboarded_skills:
        attribution = skill.source_url if skill.source_url is not None else "original"
        lines.append(
            f"- {skill.name}: {skill.local_path} — {skill.purpose} (source: {attribution})"
        )
    return lines


def _role_prompt(manifest: SquadManifest, role: Role) -> bytes:
    title = f"# {codex_role_id(manifest, role)}\n\n"
    return (title + _developer_instructions(manifest, role) + "\n").encode("utf-8")


def _role_skill(manifest: SquadManifest, role: Role) -> bytes:
    role_id = provider_role_skill_id(manifest.squad.id, role.id)
    body = (
        "---\n"
        f"name: {role_id}\n"
        f"description: {_yaml_string(_skill_description(role.description))}\n"
        "---\n\n"
        f"# {role_id}\n\n"
        "Apply the following packaged role instructions to the current task.\n\n"
        + _developer_instructions(manifest, role)
        + "\n"
    )
    return body.encode("utf-8")


def _dispatch_skill(manifest: SquadManifest, roles: tuple[Role, ...]) -> bytes:
    skill_name = provider_dispatch_skill_id(manifest.squad.id)
    sections = [
        "---",
        f"name: {skill_name}",
        "description: "
        + _yaml_string(_skill_description(f"Dispatch the packaged {manifest.squad.name} squad")),
        "---",
        "",
        f"# Dispatch {manifest.squad.name}",
        "",
        "Codex plugins do not directly install custom-agent discovery files. This skill "
        "prompt-bakes the packaged roles for standalone dispatch.",
        "",
        "Run read-only roles in any dependency-safe order. Run every mutating role "
        "sequentially, never concurrently with another mutating role.",
        "",
        *_dispatch_context_instructions(manifest),
    ]
    for role in roles:
        mode = "mutating, sequential" if _is_mutating(role) else "read-only"
        sections.extend(
            [
                "",
                f"## {codex_role_id(manifest, role)} ({mode})",
                "",
                _developer_instructions(manifest, role),
            ]
        )
    return ("\n".join(sections) + "\n").encode("utf-8")


def _yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _bounded_text(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return value[: limit - 1].rstrip() + "…"


def _skill_description(value: str) -> str:
    return _bounded_text(value.replace("<", "[").replace(">", "]"), 1024)


def _snapshot_prefix(manifest: SquadManifest) -> str:
    namespace = provider_namespace(manifest.squad.id)
    if manifest.destination is Destination.PROJECT:
        return f".squad/exports/{namespace}"
    if manifest.destination is Destination.USER:
        return f"${{HOME}}/.squad/squads/{namespace}"
    return ".squad"


def _role_context_instructions(manifest: SquadManifest, role: Role) -> list[str]:
    prefix = _snapshot_prefix(manifest)
    context_root = f"{prefix}/context"
    return [
        f"Load the vendored context index from {context_root}/index.json before working.",
        "Require squad_goal.status to be included and its snapshot body to exist. "
        f"Resolve snapshot paths relative to {prefix}.",
        f"Require the role_goals entry for {role.id} to declare a source, have status "
        "included, and have its snapshot body present.",
        "Prompt-bake the squad goal and this role goal verbatim into the task context. "
        "If any declared context is absent or unavailable, stop and report the exact "
        "status; do not work or reconstruct it from live source files.",
    ]


def _dispatch_context_instructions(manifest: SquadManifest) -> list[str]:
    prefix = _snapshot_prefix(manifest)
    context_root = f"{prefix}/context"
    return [
        "## Required vendored context",
        "",
        f"Before dispatch, read `{context_root}/index.json`. Require the squad goal to "
        "have `status: included` and load its snapshot body, resolving the recorded "
        f"`snapshot` path relative to `{prefix}`.",
        "For every selected role, require exactly one matching `role_goals` entry with a "
        "declared source, `status: included`, and an existing snapshot body. Load that "
        "body and prompt-bake the squad goal plus role goal verbatim into the role task.",
        "If the index, squad goal, selected role entry, or any declared snapshot body is "
        "missing or unavailable, stop before dispatch and report the exact recorded "
        "status. Never substitute live `.squad/goal.md` or role-goal files for the "
        "vendored snapshot.",
    ]


def _validate_runtime_path(path: str) -> None:
    candidate = PurePosixPath(path)
    if (
        not path
        or "\\" in path
        or candidate.is_absolute()
        or path != candidate.as_posix()
        or any(part in {"", ".", ".."} for part in candidate.parts)
    ):
        raise ContractError(
            f"runtime file path {path!r} must be a normalized relative path without traversal"
        )

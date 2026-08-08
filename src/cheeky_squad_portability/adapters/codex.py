"""Deterministic Codex compiler for portable squad snapshots.

The adapter only renders bytes. Destination-specific code decides whether those
bytes belong under a project's ``.codex``/``.agents`` directories or the
equivalent user directories.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from pathlib import PurePosixPath

from cheeky_squad_portability.contracts import (
    Capability,
    CodexOverride,
    Provider,
    ReasoningEffort,
    ReasoningProfile,
    Role,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.json_io import pretty_json

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

    squad_namespace = manifest.squad.id.replace(".", "-")
    raw_id = f"{squad_namespace}--{role.id}"
    if len(raw_id) <= 64:
        return raw_id
    digest = hashlib.sha256(raw_id.encode("utf-8")).hexdigest()[:12]
    return f"{raw_id[:49].rstrip('-')}--{digest}"


def compile_codex_agents(manifest: SquadManifest, roster: Roster) -> dict[str, bytes]:
    """Compile active roles to destination-neutral Codex agent TOML files."""

    _validate_inputs(manifest, roster)
    return {
        f"agents/{codex_role_id(manifest, role)}.toml": _agent_toml(manifest, role)
        for role in _active_roles(roster)
    }


def compile_codex_skills(manifest: SquadManifest, roster: Roster) -> dict[str, bytes]:
    """Compile prompt-baked role skills for project or user skill discovery."""

    _validate_inputs(manifest, roster)
    return {
        f"skills/{codex_role_id(manifest, role)}/SKILL.md": _role_skill(manifest, role)
        for role in _active_roles(roster)
    }


def compile_codex_plugin(
    manifest: SquadManifest,
    roster: Roster,
    runtime_files: Mapping[str, bytes],
) -> dict[str, bytes]:
    """Compile a standalone Codex plugin with prompt-baked role dispatch.

    Codex plugins do not directly package custom-agent discovery. Consequently
    this output intentionally contains no ``agents/*.toml`` files: packaged
    skills carry the role instructions, and the dispatch skill runs mutating
    roles sequentially.
    """

    _validate_inputs(manifest, roster)
    roles = _active_roles(roster)
    plugin_name = manifest.squad.id.replace(".", "-")
    plugin_manifest = {
        "description": manifest.squad.description
        or f"Portable Codex squad snapshot for {manifest.squad.name}",
        "name": plugin_name,
        "skills": "./skills/",
        "version": manifest.export_version,
    }
    output: dict[str, bytes] = {
        ".codex-plugin/plugin.json": pretty_json(plugin_manifest).encode("utf-8"),
        f"skills/{plugin_name}--dispatch/SKILL.md": _dispatch_skill(manifest, roles),
    }
    output.update(compile_codex_skills(manifest, roster))
    output.update(
        {
            f"roles/{codex_role_id(manifest, role)}.md": _role_prompt(manifest, role)
            for role in roles
        }
    )
    for path, content in sorted(runtime_files.items()):
        _validate_runtime_path(path)
        if not isinstance(content, bytes):
            raise ContractError(f"runtime_files[{path!r}] must be bytes")
        output[f"runtime/{path}"] = content
    return dict(sorted(output.items()))


def _validate_inputs(manifest: SquadManifest, roster: Roster) -> None:
    if Provider.CODEX not in manifest.providers:
        raise ContractError("manifest.providers must select codex for Codex compilation")
    if manifest.execution_mode is not roster.execution_mode:
        raise ContractError("manifest and roster execution modes must match")


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
    return requested or "read-only"


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
        "Requested capabilities: " + ", ".join(sorted(role.capabilities)) + ".",
        "File ownership is an instructional coordination boundary in Codex v1; "
        "it is not mechanically enforced.",
        "Work only within these instructed paths: " + ", ".join(role.file_ownership.include) + ".",
    ]
    if role.file_ownership.exclude:
        lines.append("Do not modify these paths: " + ", ".join(role.file_ownership.exclude) + ".")
    if role.goal_ref is not None:
        lines.append(f"Read the role goal from {role.goal_ref} when that file is available.")
    if role.environment is not None:
        lines.extend(_environment_instructions(role))
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
        variables = ", ".join(f"{key}={value}" for key, value in environment.variables)
        lines.append(f"Environment values: {variables}.")
    if environment.context:
        context = ", ".join(
            f"{item.source} -> {item.target} ({item.kind})" for item in environment.context
        )
        lines.append(f"Expected context material: {context}.")
    if environment.tools:
        rendered_tools = []
        for tool in environment.tools:
            details = [tool.kind]
            if tool.verify is not None:
                details.append(f"verify: {tool.verify}")
            if tool.install is not None:
                details.append(f"install: {tool.install}")
            rendered_tools.append(f"{tool.name} ({'; '.join(details)})")
        tools = ", ".join(rendered_tools)
        lines.append(f"Expected tools: {tools}.")
    return lines


def _role_prompt(manifest: SquadManifest, role: Role) -> bytes:
    title = f"# {codex_role_id(manifest, role)}\n\n"
    return (title + _developer_instructions(manifest, role) + "\n").encode("utf-8")


def _role_skill(manifest: SquadManifest, role: Role) -> bytes:
    role_id = codex_role_id(manifest, role)
    body = (
        "---\n"
        f"name: {role_id}\n"
        f"description: {_yaml_string(role.description)}\n"
        "---\n\n"
        f"# {role_id}\n\n"
        "Apply the following packaged role instructions to the current task.\n\n"
        + _developer_instructions(manifest, role)
        + "\n"
    )
    return body.encode("utf-8")


def _dispatch_skill(manifest: SquadManifest, roles: tuple[Role, ...]) -> bytes:
    plugin_name = manifest.squad.id.replace(".", "-")
    sections = [
        "---",
        f"name: {plugin_name}--dispatch",
        f"description: {_yaml_string(f'Dispatch the packaged {manifest.squad.name} squad')}",
        "---",
        "",
        f"# Dispatch {manifest.squad.name}",
        "",
        "Codex plugins do not directly install custom-agent discovery files. This skill "
        "prompt-bakes the packaged roles for standalone dispatch.",
        "",
        "Run read-only roles in any dependency-safe order. Run every mutating role "
        "sequentially, never concurrently with another mutating role.",
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

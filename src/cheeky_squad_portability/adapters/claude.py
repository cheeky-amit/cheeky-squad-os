"""Pure compiler for Claude agent files and standalone squad plugins."""

from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import PurePosixPath

from cheeky_squad_portability.contracts import (
    Capability,
    ClaudeOverride,
    Destination,
    Provider,
    ReasoningEffort,
    ReasoningProfile,
    Role,
    Roster,
    RuntimeOwner,
    SquadManifest,
)
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.json_io import JsonValue, pretty_json
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.namespace import provider_namespace, provider_role_id

_CAPABILITY_TO_TOOL = {
    Capability.FILESYSTEM_EDIT.value: "Edit",
    Capability.FILESYSTEM_GLOB.value: "Glob",
    Capability.FILESYSTEM_READ.value: "Read",
    Capability.FILESYSTEM_SEARCH.value: "Grep",
    Capability.FILESYSTEM_WRITE.value: "Write",
    Capability.NETWORK_FETCH.value: "WebFetch",
    Capability.NETWORK_SEARCH.value: "WebSearch",
    Capability.NOTEBOOK_EDIT.value: "NotebookEdit",
    Capability.SHELL_EXECUTE.value: "Bash",
}
_PROFILE_TO_MODEL = {
    ReasoningProfile.FAST: "haiku",
    ReasoningProfile.BALANCED: "sonnet",
    ReasoningProfile.DEEP: "opus",
    ReasoningProfile.INHERIT: "inherit",
}
_MUTATING_TOOLS = {"Bash", "Edit", "NotebookEdit", "Write"}
_REQUIRED_HOOKS = (
    "hooks/permission-request.sh",
    "hooks/session-start.sh",
    "hooks/user-prompt-submit.sh",
)
_RUNTIME_PREFIXES = ("commands/", "hooks/", "scripts/", "skills/", "templates/")


def _require_claude(manifest: SquadManifest) -> None:
    if Provider.CLAUDE not in manifest.providers:
        raise ContractError("Claude compilation requires claude in manifest.providers")


def _canonical_roster(manifest: SquadManifest, roster: Roster | object) -> Roster:
    canonical = roster if isinstance(roster, Roster) else load_roster(roster)
    if canonical.execution_mode is not manifest.execution_mode:
        raise ContractError("manifest and roster execution_mode must match")
    return canonical


def _safe_artifact_path(path: str) -> str:
    if not path or "\\" in path:
        raise ContractError("runtime artifact paths must be POSIX relative paths")
    candidate = PurePosixPath(path)
    if candidate.is_absolute() or candidate == PurePosixPath(".") or ".." in candidate.parts:
        raise ContractError("runtime artifact paths must stay inside the plugin")
    normalized = candidate.as_posix()
    if normalized != path:
        raise ContractError("runtime artifact paths must be normalized")
    return normalized


def _claude_override(role: Role) -> ClaudeOverride | None:
    if role.provider_overrides is None:
        return None
    return role.provider_overrides.claude


def _tools(role: Role) -> tuple[str, ...]:
    override = _claude_override(role)
    if override is not None and override.tools:
        return override.tools

    tools: list[str] = []
    for capability in role.capabilities:
        tool = _CAPABILITY_TO_TOOL.get(capability)
        if tool is not None:
            tools.append(tool)
            continue
        if capability in {
            Capability.EXTERNAL_MCP.value,
            Capability.PROVIDER_CLAUDE_TOOL.value,
        }:
            raise ContractError(
                f"role {role.id} needs an exact Claude tool override for {capability}"
            )
        raise ContractError(f"role {role.id} has no Claude mapping for {capability}")
    if not tools:
        raise ContractError(f"role {role.id} compiles to an empty Claude tool allowlist")
    return tuple(dict.fromkeys(tools))


def _model(role: Role) -> str:
    override = _claude_override(role)
    if override is not None and override.model is not None:
        return override.model
    return _PROFILE_TO_MODEL[role.reasoning.profile]


def _yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _yaml_list(values: tuple[str, ...]) -> str:
    return json.dumps(list(values), ensure_ascii=False, separators=(",", ":"))


def claude_role_id(manifest: SquadManifest, role: Role) -> str:
    """Return the stable discovery ID used for project, user, and plugin agents."""

    _require_claude(manifest)
    return provider_role_id(manifest.squad.id, role.id)


def _environment_lines(role: Role) -> list[str]:
    if role.environment is None:
        return []
    environment = role.environment
    lines = ["", "## Environment", "", f"Workspace: `{environment.workspace}`."]
    if environment.directories:
        lines.append("Expected directories: " + ", ".join(environment.directories) + ".")
    if environment.variables:
        variable_names = ", ".join(f"`{key}`" for key, _ in environment.variables)
        lines.append(
            "Load the provisioned workspace environment before running tools. "
            f"Expected variable names: {variable_names}. Values are intentionally not embedded."
        )
    if environment.tools:
        tools = ", ".join(f"{tool.name} ({tool.kind})" for tool in environment.tools)
        lines.append(f"Expected tools: {tools}.")
    return lines


def _snapshot_root(manifest: SquadManifest) -> str:
    namespace = provider_namespace(manifest.squad.id)
    if manifest.destination is Destination.PROJECT:
        return f"${{CLAUDE_PROJECT_DIR}}/.squad/exports/{namespace}"
    if manifest.destination is Destination.USER:
        return f"${{HOME}}/.squad/squads/{namespace}"
    if manifest.destination is Destination.PLUGIN:
        return "${CLAUDE_PLUGIN_ROOT}/.squad"
    raise ContractError("session exports do not compile discoverable Claude agents")


def _context_lines(manifest: SquadManifest, role: Role) -> list[str]:
    snapshot_root = _snapshot_root(manifest)
    context_index = f"{snapshot_root}/context/index.json"
    return [
        "## Required vendored context",
        "",
        "Resolve the snapshot root from the provider anchor shown below, independently",
        "of the current working directory. Do not replace the anchor with the current",
        "repository or another live squad directory.",
        "",
        f"- Snapshot root: `{snapshot_root}`",
        f"- Context index: `{context_index}`",
        "",
        "Before doing any role work, read and validate the context index. Require",
        "`schema_version: 1`, require `squad_goal.status` to be `included`, and require",
        "its declared snapshot body to exist under the snapshot root.",
        "",
        f"Require exactly one `role_goals` entry whose `role_id` is `{role.id}`. It must",
        "declare its canonical source, have `status: included`, and name an existing",
        "snapshot body under the snapshot root. Resolve every recorded snapshot path",
        "relative to that root and reject absolute paths or traversal.",
        "",
        "Load the squad-goal and matching role-goal bodies and include them verbatim in",
        "the task context. If the index is missing or malformed, either entry is absent",
        "or unavailable, or either body cannot be loaded safely, stop before working and",
        "report the exact failure. Never fall back to live `.squad/goal.md` or role-goal",
        "files.",
        "",
    ]


def _render_agent(manifest: SquadManifest, role: Role) -> bytes:
    role_id = claude_role_id(manifest, role)
    tools = _tools(role)
    model = _model(role)
    lines = [
        "---",
        f"name: {_yaml_string(role_id)}",
        f"description: {_yaml_string(role.description)}",
        f"tools: {_yaml_list(tools)}",
        f"model: {_yaml_string(model)}",
    ]
    if role.reasoning.effort is not ReasoningEffort.INHERIT:
        lines.append(f"effort: {_yaml_string(role.reasoning.effort.value)}")
    override = _claude_override(role)
    if override is not None and override.isolation is not None:
        lines.append(f"isolation: {_yaml_string(override.isolation)}")
    lines.extend(
        [
            "---",
            "",
            f"# {role_id}",
            "",
            role.purpose,
            "",
            "You are a packaged cheeky-squad-os role. This file is a vendored snapshot;",
            "it has no dependency on the squad generator.",
            "",
            "## Assignment",
            "",
            role.description,
            "",
            *_context_lines(manifest, role),
            "## File ownership",
            "",
            "Treat these paths as a hard working boundary:",
            "",
        ]
    )
    lines.extend(f"- `{path}`" for path in role.file_ownership.include)
    if role.file_ownership.exclude:
        lines.extend(["", "Excluded even when an include pattern is broader:", ""])
        lines.extend(f"- `{path}`" for path in role.file_ownership.exclude)
    lines.extend(
        [
            "",
            "Ask before touching anything outside that boundary. File ownership is instructional",
            "unless the active Claude runtime independently gates the write.",
            "",
            "## Provider contract",
            "",
            f"- Claude tools: `{', '.join(tools)}`",
            f"- Claude model: `{model}`",
            f"- Execution cadence: `{manifest.execution_mode.value}`",
        ]
    )
    if _MUTATING_TOOLS.isdisjoint(tools):
        lines.extend(
            [
                "",
                "This is a read-only role: return findings to the caller; do not create or",
                "edit files.",
            ]
        )
    else:
        lines.extend(
            [
                "",
                "## Engagement record",
                "",
                f"Before your first write, publish `.squad/role-plan-{role.id}.md` with the",
                "artifacts you intend to change. This canonical, un-namespaced path is the",
                "bootstrap recognized by the vendored PermissionRequest runtime.",
                "",
                "This is a mutating role. Make the smallest change and keep writes inside the",
                "declared ownership paths, and report every artifact changed.",
            ]
        )
    lines.extend(_environment_lines(role))
    lines.extend(
        [
            "",
            "The runtime gates auto-approval eligibility; it does not block a human-approved",
            "out-of-scope write. Report that distinction exactly.",
            "",
        ]
    )
    return "\n".join(lines).encode("utf-8")


def compile_claude_agents(manifest: SquadManifest, roster: Roster | object) -> dict[str, bytes]:
    """Compile active roles to Claude's provider-relative ``agents/`` layout."""

    _require_claude(manifest)
    canonical = _canonical_roster(manifest, roster)
    artifacts: dict[str, bytes] = {}
    for role in sorted((item for item in canonical.roles if item.active), key=lambda item: item.id):
        role_id = claude_role_id(manifest, role)
        artifacts[f"agents/{role_id}.md"] = _render_agent(manifest, role)
    return artifacts


def _hook_manifest() -> dict[str, JsonValue]:
    root = "${CLAUDE_PLUGIN_ROOT}"
    return {
        "SessionStart": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"{root}/hooks/session-start.sh",
                        "timeout": 5,
                    }
                ]
            }
        ],
        "UserPromptSubmit": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"{root}/hooks/user-prompt-submit.sh",
                        "timeout": 3,
                    }
                ]
            }
        ],
        "PermissionRequest": [
            {
                "matcher": "Bash|Edit|Write",
                "hooks": [
                    {
                        "type": "command",
                        "command": f"{root}/hooks/permission-request.sh",
                        "timeout": 3,
                    }
                ],
            }
        ],
    }


def _plugin_manifest(manifest: SquadManifest) -> bytes:
    plugin: dict[str, JsonValue] = {
        "name": provider_namespace(manifest.squad.id),
        "displayName": manifest.squad.name,
        "description": manifest.squad.description or f"Portable squad: {manifest.squad.name}",
        "version": manifest.export_version,
        "author": {"name": "cheeky-squad-os export"},
        "license": "MIT",
        "keywords": ["squad", "portable-squad", "claude-code-plugin"],
    }
    if manifest.runtime_owner is RuntimeOwner.CLAUDE:
        plugin["hooks"] = _hook_manifest()
    return pretty_json(plugin).encode("utf-8")


def _activation_readme(manifest: SquadManifest, roster: Roster) -> bytes:
    role_ids = [
        claude_role_id(manifest, role)
        for role in sorted((item for item in roster.roles if item.active), key=lambda item: item.id)
    ]
    hook_status = (
        "Claude owns the shared runtime, so this package registers the vendored lifecycle hooks."
        if manifest.runtime_owner is RuntimeOwner.CLAUDE
        else "Claude does not own the shared runtime, so this package registers no lifecycle hooks."
    )
    lines = [
        f"# {manifest.squad.name} — Claude package",
        "",
        "This is a self-contained, vendored squad snapshot. Generation did not install or",
        "enable anything, and using it does not require cheeky-squad-os to remain installed.",
        "",
        "## Activate deliberately",
        "",
        "Inspect it, then launch Claude Code with this directory via `--plugin-dir` for a",
        "temporary activation. Use your approved plugin installation flow only if you want the",
        "package to persist. Installation and enablement are intentionally separate from export.",
        "",
        hook_status,
        "",
        "## Packaged roles",
        "",
    ]
    lines.extend(f"- `{role_id}`" for role_id in role_ids)
    lines.extend(["", f"Export version: `{manifest.export_version}`", ""])
    return "\n".join(lines).encode("utf-8")


def _provider_role_map(manifest: SquadManifest, roster: Roster) -> bytes:
    """Map provider discovery IDs back to canonical role IDs for vendored hooks."""

    roles = {
        claude_role_id(manifest, role): role.id
        for role in sorted((item for item in roster.roles if item.active), key=lambda item: item.id)
    }
    return pretty_json({"schema_version": 1, "roles": roles}).encode("utf-8")


def _vendored_runtime(
    manifest: SquadManifest, runtime_files: Mapping[str, bytes]
) -> dict[str, bytes]:
    normalized = {_safe_artifact_path(path): content for path, content in runtime_files.items()}
    if "LICENSE" not in normalized:
        raise ContractError("a self-contained Claude plugin requires LICENSE in runtime_files")
    if manifest.runtime_owner is RuntimeOwner.CLAUDE:
        missing = [path for path in _REQUIRED_HOOKS if path not in normalized]
        if missing:
            raise ContractError(f"Claude runtime owner is missing hook artifact: {missing[0]}")

    artifacts: dict[str, bytes] = {}
    for path in sorted(normalized):
        if path == "LICENSE":
            artifacts[path] = normalized[path]
            continue
        if not path.startswith(_RUNTIME_PREFIXES):
            continue
        if path.startswith("hooks/") and manifest.runtime_owner is not RuntimeOwner.CLAUDE:
            continue
        artifacts[path] = normalized[path]
    return artifacts


def compile_claude_plugin(
    manifest: SquadManifest,
    roster: Roster | object,
    runtime_files: Mapping[str, bytes],
) -> dict[str, bytes]:
    """Compile a standalone Claude plugin without installing or enabling it."""

    _require_claude(manifest)
    canonical = _canonical_roster(manifest, roster)
    artifacts = _vendored_runtime(manifest, runtime_files)
    generated = {
        ".claude-plugin/plugin.json": _plugin_manifest(manifest),
        ".squad/provider-role-map.json": _provider_role_map(manifest, canonical),
        "README.md": _activation_readme(manifest, canonical),
        **compile_claude_agents(manifest, canonical),
    }
    collisions = sorted(set(artifacts) & set(generated))
    if collisions:
        raise ContractError(f"runtime artifact collides with generated output: {collisions[0]}")
    artifacts.update(generated)
    return dict(sorted(artifacts.items()))

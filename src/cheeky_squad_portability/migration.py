"""Pure, deterministic migration from the legacy Claude-shaped roster."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

from cheeky_squad_portability.contracts import (
    ClaudeOverride,
    Environment,
    EnvironmentContext,
    EnvironmentTool,
    ExecutionMode,
    FileOwnership,
    ProviderOverrides,
    Reasoning,
    ReasoningEffort,
    ReasoningProfile,
    Role,
    Roster,
    normalize_capabilities,
)
from cheeky_squad_portability.errors import ContractError

_TOOL_CAPABILITIES = {
    "Bash": "shell.execute",
    "Edit": "filesystem.edit",
    "Glob": "filesystem.glob",
    "Grep": "filesystem.search",
    "Read": "filesystem.read",
    "Write": "filesystem.write",
}


def _mapping(value: object, path: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or any(not isinstance(key, str) for key in value):
        raise ContractError(f"{path} must be an object with string keys")
    return value


def _sequence(value: object, path: str) -> Sequence[object]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        raise ContractError(f"{path} must be an array")
    return value


def _text(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractError(f"{path} must be a non-empty string")
    return value


def _texts(value: object, path: str) -> tuple[str, ...]:
    return tuple(
        _text(item, f"{path}[{index}]") for index, item in enumerate(_sequence(value, path))
    )


def _reasoning(model: str, effort: object) -> Reasoning:
    if model == "inherit":
        profile = ReasoningProfile.INHERIT
    elif model == "haiku":
        profile = ReasoningProfile.FAST
    elif model == "sonnet":
        profile = ReasoningProfile.BALANCED
    else:
        profile = ReasoningProfile.DEEP
    try:
        parsed_effort = ReasoningEffort("inherit" if effort is None else effort)
    except ValueError as error:
        raise ContractError("legacy role effort is invalid") from error
    return Reasoning(profile=profile, effort=parsed_effort)


def _capabilities(tools: tuple[str, ...]) -> tuple[str, ...]:
    capabilities: list[str] = []
    for tool in tools:
        mapped = _TOOL_CAPABILITIES.get(tool)
        if mapped is not None:
            capabilities.append(mapped)
        elif tool.startswith("mcp__"):
            capabilities.append("external.mcp")
        else:
            capabilities.append("provider.claude.tool")
    return normalize_capabilities(capabilities)


def _environment(value: object, path: str) -> Environment:
    data = _mapping(value, path)
    raw_variables = _mapping(data.get("env", {}), f"{path}.env")
    variables = tuple(
        sorted(
            (
                _text(key, f"{path}.env key"),
                item if isinstance(item, str) else _raise_text(f"{path}.env.{key}"),
            )
            for key, item in raw_variables.items()
        )
    )
    contexts = tuple(
        EnvironmentContext(
            source=_text(_mapping(item, f"{path}.context[{index}]").get("from"), "context.from"),
            target=_text(_mapping(item, f"{path}.context[{index}]").get("into"), "context.into"),
            kind=_text(_mapping(item, f"{path}.context[{index}]").get("kind"), "context.kind"),
        )
        for index, item in enumerate(_sequence(data.get("context", []), f"{path}.context"))
    )
    tools = tuple(
        _environment_tool(item, f"{path}.tools[{index}]")
        for index, item in enumerate(_sequence(data.get("tools", []), f"{path}.tools"))
    )
    return Environment(
        workspace=_text(data.get("workspace"), f"{path}.workspace").rstrip("/"),
        directories=_texts(data.get("dirs", []), f"{path}.dirs"),
        variables=variables,
        context=contexts,
        tools=tools,
    )


def _raise_text(path: str) -> str:
    raise ContractError(f"{path} must be a string")


def _environment_tool(value: object, path: str) -> EnvironmentTool:
    data = _mapping(value, path)
    return EnvironmentTool(
        name=_text(data.get("name"), f"{path}.name"),
        kind=_text(data.get("kind"), f"{path}.kind"),
        verify=_optional_text(data.get("verify"), f"{path}.verify"),
        install=_optional_text(data.get("install"), f"{path}.install"),
    )


def _optional_text(value: object, path: str) -> str | None:
    return None if value is None else _text(value, path)


def _legacy_role(value: object, index: int) -> Role:
    path = f"legacy roster.roles[{index}]"
    data = _mapping(value, path)
    name = _text(data.get("name"), f"{path}.name")
    purpose = _text(data.get("purpose"), f"{path}.purpose")
    tools = _texts(data.get("tools"), f"{path}.tools")
    model = _text(data.get("model"), f"{path}.model")
    active = data.get("active", True)
    if not isinstance(active, bool):
        raise ContractError(f"{path}.active must be a boolean")
    provider = ClaudeOverride(
        model=model,
        tools=tools,
        agent_file=_optional_text(data.get("agent_file"), f"{path}.agent_file"),
        isolation=_optional_text(data.get("isolation"), f"{path}.isolation"),
    )
    return Role(
        id=name,
        purpose=purpose,
        description=purpose,
        file_ownership=FileOwnership(include=_texts(data.get("file_scope"), f"{path}.file_scope")),
        capabilities=_capabilities(tools),
        reasoning=_reasoning(model, data.get("effort")),
        active=active,
        goal_ref=_optional_text(data.get("role_goal"), f"{path}.role_goal"),
        environment=(
            None
            if data.get("environment") is None
            else _environment(data.get("environment"), f"{path}.environment")
        ),
        provider_overrides=ProviderOverrides(claude=provider),
        created=_optional_text(data.get("created"), f"{path}.created"),
    )


def migrate_legacy_roster(value: object) -> Roster:
    """Return a v2 roster without mutating or writing the legacy input."""

    data = _mapping(value, "legacy roster")
    try:
        execution_mode = ExecutionMode(_text(data.get("mode"), "legacy roster.mode"))
    except ValueError as error:
        raise ContractError("legacy roster.mode is invalid") from error
    return Roster(
        squad_goal_ref=_text(data.get("squad_goal_ref"), "legacy roster.squad_goal_ref"),
        execution_mode=execution_mode,
        roles=tuple(
            _legacy_role(item, index)
            for index, item in enumerate(_sequence(data.get("roles"), "legacy roster.roles"))
        ),
        created=_optional_text(data.get("created"), "legacy roster.created"),
    )


def load_roster(value: object) -> Roster:
    """Load v2 directly or deterministically migrate a schema-less legacy roster."""

    data = _mapping(value, "roster")
    if data.get("schema_version") == 2:
        return Roster.from_dict(data)
    return migrate_legacy_roster(data)

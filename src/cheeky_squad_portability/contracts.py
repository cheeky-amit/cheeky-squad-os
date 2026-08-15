"""Frozen, provider-neutral squad contracts.

These types are the compiler boundary. They deliberately do not write files or
know where a provider discovers agents; provider adapters consume them later.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from enum import StrEnum

from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.json_io import JsonValue, sorted_unique
from cheeky_squad_portability.namespace import SQUAD_ID_MAX_LENGTH

_ROLE_ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
_SQUAD_ID_PATTERN = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)*$"
)
_SEMVER_PATTERN = re.compile(
    r"^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)

MAX_ACTIVE_ROLES = 5
"""A squad holds at most this many active roles. Enforced at decomposition
(squad-onboard), registration (squad-role preflight), and the roster write
(squad-roster Add). Over-cap rosters are grandfathered: this module never
hard-fails validation on an over-cap roster, so a legacy squad keeps working."""


class ExecutionMode(StrEnum):
    """How often a squad executes; independent from where it is exported."""

    ONE_TIME = "one-time"
    MULTI_USE = "multi-use"
    EVERGREEN = "evergreen"


class Destination(StrEnum):
    """Where a compiled snapshot may be made available."""

    SESSION = "session"
    PROJECT = "project"
    USER = "user"
    PLUGIN = "plugin"


class Provider(StrEnum):
    CLAUDE = "claude"
    CODEX = "codex"


class RuntimeOwner(StrEnum):
    """The one selected provider allowed to own shared lifecycle runtime."""

    CLAUDE = "claude"
    CODEX = "codex"


class Capability(StrEnum):
    """Portable capabilities understood by provider adapters."""

    FILESYSTEM_EDIT = "filesystem.edit"
    FILESYSTEM_GLOB = "filesystem.glob"
    FILESYSTEM_READ = "filesystem.read"
    FILESYSTEM_SEARCH = "filesystem.search"
    FILESYSTEM_WRITE = "filesystem.write"
    NETWORK_FETCH = "network.fetch"
    NETWORK_SEARCH = "network.search"
    NOTEBOOK_EDIT = "notebook.edit"
    SHELL_EXECUTE = "shell.execute"
    EXTERNAL_MCP = "external.mcp"
    PROVIDER_CLAUDE_TOOL = "provider.claude.tool"


class ReasoningProfile(StrEnum):
    FAST = "fast"
    BALANCED = "balanced"
    DEEP = "deep"
    INHERIT = "inherit"


class ReasoningEffort(StrEnum):
    INHERIT = "inherit"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    XHIGH = "xhigh"
    MAX = "max"


def _object(value: object, path: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise ContractError(f"{path} must be an object")
    for key in value:
        if not isinstance(key, str):
            raise ContractError(f"{path} keys must be strings")
    return value


def _array(value: object, path: str) -> Sequence[object]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        raise ContractError(f"{path} must be an array")
    return value


def _string(value: object, path: str, *, nonempty: bool = True) -> str:
    if not isinstance(value, str) or (nonempty and not value.strip()):
        qualifier = "a non-empty string" if nonempty else "a string"
        raise ContractError(f"{path} must be {qualifier}")
    return value


def _optional_string(value: object, path: str) -> str | None:
    if value is None:
        return None
    return _string(value, path)


def _boolean(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise ContractError(f"{path} must be a boolean")
    return value


def _string_tuple(value: object, path: str, *, allow_empty: bool = False) -> tuple[str, ...]:
    raw = _array(value, path)
    strings = tuple(_string(item, f"{path}[{index}]") for index, item in enumerate(raw))
    if not allow_empty and not strings:
        raise ContractError(f"{path} must contain at least one item")
    if len(strings) != len(set(strings)):
        raise ContractError(f"{path} must not contain duplicates")
    return strings


def _enum_member(enum_type: type[StrEnum], value: object, path: str) -> StrEnum:
    text = _string(value, path)
    try:
        return enum_type(text)
    except ValueError as error:
        choices = ", ".join(item.value for item in enum_type)
        raise ContractError(f"{path} must be one of: {choices}") from error


def _reject_unknown(data: Mapping[str, object], allowed: set[str], path: str) -> None:
    unknown = sorted(set(data) - allowed)
    if unknown:
        raise ContractError(f"{path} has unknown fields: {', '.join(unknown)}")


def _relative_path(
    value: object,
    path: str,
    *,
    allow_dot: bool = False,
    allow_glob: bool = True,
) -> str:
    """Validate a normalized project-relative POSIX path or glob."""

    text = _string(value, path)
    if text == "." and allow_dot:
        return text
    if (
        text.startswith(("/", "~"))
        or "\\" in text
        or "//" in text
        or any(ord(character) < 32 for character in text)
        or any(part in {"", ".", ".."} for part in text.split("/"))
    ):
        raise ContractError(f"{path} must be a normalized project-relative path without traversal")
    if not allow_glob and any(character in text for character in "*?[]"):
        raise ContractError(f"{path} must be a literal project-relative path without globs")
    return text


@dataclass(frozen=True)
class SquadIdentity:
    id: str
    name: str
    description: str | None = None

    def __post_init__(self) -> None:
        if not _SQUAD_ID_PATTERN.fullmatch(self.id):
            raise ContractError("squad.id must be a lowercase namespaced identifier")
        if len(self.id) > SQUAD_ID_MAX_LENGTH:
            raise ContractError(f"squad.id must contain at most {SQUAD_ID_MAX_LENGTH} characters")
        _string(self.name, "squad.name")
        if self.description is not None:
            _string(self.description, "squad.description")

    @classmethod
    def from_dict(cls, value: object, path: str = "squad") -> SquadIdentity:
        data = _object(value, path)
        _reject_unknown(data, {"id", "name", "description"}, path)
        return cls(
            id=_string(data.get("id"), f"{path}.id"),
            name=_string(data.get("name"), f"{path}.name"),
            description=_optional_string(data.get("description"), f"{path}.description"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {"id": self.id, "name": self.name}
        if self.description is not None:
            result["description"] = self.description
        return result


@dataclass(frozen=True)
class SquadManifest:
    squad: SquadIdentity
    execution_mode: ExecutionMode
    destination: Destination
    providers: tuple[Provider, ...]
    runtime_owner: RuntimeOwner
    export_version: str
    schema_version: int = field(default=2, init=False)

    def __post_init__(self) -> None:
        if not self.providers:
            raise ContractError("providers must contain at least one provider")
        if len(self.providers) != len(set(self.providers)):
            raise ContractError("providers must not contain duplicates")
        if Provider(self.runtime_owner.value) not in self.providers:
            raise ContractError("runtime_owner must be one of the selected providers")
        if not _SEMVER_PATTERN.fullmatch(self.export_version):
            raise ContractError("export_version must be semantic version text")

    @classmethod
    def from_dict(cls, value: object) -> SquadManifest:
        data = _object(value, "manifest")
        _reject_unknown(
            data,
            {
                "schema_version",
                "squad",
                "execution_mode",
                "destination",
                "providers",
                "runtime_owner",
                "export_version",
            },
            "manifest",
        )
        if data.get("schema_version") != 2:
            raise ContractError("manifest.schema_version must be 2")
        providers = tuple(
            Provider(_enum_member(Provider, item, f"manifest.providers[{index}]").value)
            for index, item in enumerate(_array(data.get("providers"), "manifest.providers"))
        )
        return cls(
            squad=SquadIdentity.from_dict(data.get("squad")),
            execution_mode=ExecutionMode(
                _enum_member(
                    ExecutionMode,
                    data.get("execution_mode"),
                    "manifest.execution_mode",
                ).value
            ),
            destination=Destination(
                _enum_member(Destination, data.get("destination"), "manifest.destination").value
            ),
            providers=providers,
            runtime_owner=RuntimeOwner(
                _enum_member(
                    RuntimeOwner,
                    data.get("runtime_owner"),
                    "manifest.runtime_owner",
                ).value
            ),
            export_version=_string(data.get("export_version"), "manifest.export_version"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {
            "schema_version": self.schema_version,
            "squad": self.squad.to_dict(),
            "execution_mode": self.execution_mode.value,
            "destination": self.destination.value,
            "providers": sorted(provider.value for provider in self.providers),
            "runtime_owner": self.runtime_owner.value,
            "export_version": self.export_version,
        }


@dataclass(frozen=True)
class FileOwnership:
    include: tuple[str, ...]
    exclude: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not self.include:
            raise ContractError("file_ownership.include must contain at least one path")
        for field_name, paths in (("include", self.include), ("exclude", self.exclude)):
            if len(paths) != len(set(paths)):
                raise ContractError(f"file_ownership.{field_name} must not contain duplicates")
            for index, path in enumerate(paths):
                _relative_path(path, f"file_ownership.{field_name}[{index}]")

    @classmethod
    def from_dict(cls, value: object, path: str) -> FileOwnership:
        data = _object(value, path)
        _reject_unknown(data, {"include", "exclude"}, path)
        return cls(
            include=_string_tuple(data.get("include"), f"{path}.include"),
            exclude=_string_tuple(data.get("exclude", []), f"{path}.exclude", allow_empty=True),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {"include": list(self.include), "exclude": list(self.exclude)}


@dataclass(frozen=True)
class Reasoning:
    profile: ReasoningProfile
    effort: ReasoningEffort = ReasoningEffort.INHERIT

    @classmethod
    def from_dict(cls, value: object, path: str) -> Reasoning:
        data = _object(value, path)
        _reject_unknown(data, {"profile", "effort"}, path)
        return cls(
            profile=ReasoningProfile(
                _enum_member(ReasoningProfile, data.get("profile"), f"{path}.profile").value
            ),
            effort=ReasoningEffort(
                _enum_member(
                    ReasoningEffort,
                    data.get("effort", ReasoningEffort.INHERIT.value),
                    f"{path}.effort",
                ).value
            ),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {"profile": self.profile.value, "effort": self.effort.value}


@dataclass(frozen=True)
class EnvironmentContext:
    source: str
    target: str
    kind: str

    def __post_init__(self) -> None:
        if self.kind not in {"copy", "link", "fetch"}:
            raise ContractError("environment.context.kind must be copy, link, or fetch")
        if self.kind == "fetch":
            _string(self.source, "environment.context.source")
        else:
            _relative_path(self.source, "environment.context.source", allow_glob=False)
        _relative_path(self.target, "environment.context.target", allow_dot=True)

    @classmethod
    def from_dict(cls, value: object, path: str) -> EnvironmentContext:
        data = _object(value, path)
        _reject_unknown(data, {"source", "target", "kind"}, path)
        return cls(
            source=_string(data.get("source"), f"{path}.source"),
            target=_string(data.get("target"), f"{path}.target"),
            kind=_string(data.get("kind"), f"{path}.kind"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {"source": self.source, "target": self.target, "kind": self.kind}


@dataclass(frozen=True)
class EnvironmentTool:
    name: str
    kind: str
    verify: str | None = None
    install: str | None = None

    def __post_init__(self) -> None:
        _string(self.name, "environment.tools.name")
        if self.kind not in {"local", "system", "mcp"}:
            raise ContractError("environment.tools.kind must be local, system, or mcp")
        if self.verify is not None:
            _string(self.verify, "environment.tools.verify")
        if self.install is not None:
            _string(self.install, "environment.tools.install")

    @classmethod
    def from_dict(cls, value: object, path: str) -> EnvironmentTool:
        data = _object(value, path)
        _reject_unknown(data, {"name", "kind", "verify", "install"}, path)
        return cls(
            name=_string(data.get("name"), f"{path}.name"),
            kind=_string(data.get("kind"), f"{path}.kind"),
            verify=_optional_string(data.get("verify"), f"{path}.verify"),
            install=_optional_string(data.get("install"), f"{path}.install"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {"name": self.name, "kind": self.kind}
        if self.verify is not None:
            result["verify"] = self.verify
        if self.install is not None:
            result["install"] = self.install
        return result


@dataclass(frozen=True)
class OnboardedSkill:
    """An external, open-source skill a role researched, adapted, and had approved."""

    name: str
    local_path: str
    purpose: str
    approval_mode: str
    kind: str = "knowledge"
    source_url: str | None = None
    approved_at: str | None = None

    def __post_init__(self) -> None:
        if not _ROLE_ID_PATTERN.fullmatch(self.name):
            raise ContractError("onboarded_skills.name must be lowercase kebab-case")
        _relative_path(self.local_path, "onboarded_skills.local_path", allow_glob=False)
        _string(self.purpose, "onboarded_skills.purpose")
        if self.approval_mode not in {"user", "auto"}:
            raise ContractError("onboarded_skills.approval_mode must be user or auto")
        if self.kind not in {"knowledge", "execution"}:
            raise ContractError("onboarded_skills.kind must be knowledge or execution")
        if self.source_url is not None:
            _string(self.source_url, "onboarded_skills.source_url")
        if self.approved_at is not None:
            _string(self.approved_at, "onboarded_skills.approved_at")

    @classmethod
    def from_dict(cls, value: object, path: str) -> OnboardedSkill:
        data = _object(value, path)
        _reject_unknown(
            data,
            {
                "name",
                "source_url",
                "local_path",
                "purpose",
                "approval_mode",
                "kind",
                "approved_at",
            },
            path,
        )
        return cls(
            name=_string(data.get("name"), f"{path}.name"),
            local_path=_string(data.get("local_path"), f"{path}.local_path"),
            purpose=_string(data.get("purpose"), f"{path}.purpose"),
            approval_mode=_string(data.get("approval_mode"), f"{path}.approval_mode"),
            kind=_string(data.get("kind", "knowledge"), f"{path}.kind"),
            source_url=_optional_string(data.get("source_url"), f"{path}.source_url"),
            approved_at=_optional_string(data.get("approved_at"), f"{path}.approved_at"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {
            "name": self.name,
            "local_path": self.local_path,
            "purpose": self.purpose,
            "approval_mode": self.approval_mode,
            "kind": self.kind,
        }
        if self.source_url is not None:
            result["source_url"] = self.source_url
        if self.approved_at is not None:
            result["approved_at"] = self.approved_at
        return result


@dataclass(frozen=True)
class Environment:
    workspace: str
    directories: tuple[str, ...] = ()
    variables: tuple[tuple[str, str], ...] = ()
    context: tuple[EnvironmentContext, ...] = ()
    tools: tuple[EnvironmentTool, ...] = ()

    def __post_init__(self) -> None:
        _relative_path(self.workspace, "environment.workspace")
        if len(self.directories) != len(set(self.directories)):
            raise ContractError("environment.directories must not contain duplicates")
        for index, directory in enumerate(self.directories):
            _relative_path(directory, f"environment.directories[{index}]")
        if len(self.variables) != len({key for key, _ in self.variables}):
            raise ContractError("environment.variables must not contain duplicate keys")
        for key, _ in self.variables:
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                raise ContractError("environment.variables keys must be valid shell identifiers")

    @classmethod
    def from_dict(cls, value: object, path: str) -> Environment:
        data = _object(value, path)
        _reject_unknown(data, {"workspace", "directories", "variables", "context", "tools"}, path)
        raw_variables = _object(data.get("variables", {}), f"{path}.variables")
        variables = tuple(
            sorted(
                (
                    _string(key, f"{path}.variables key"),
                    _string(item, f"{path}.variables.{key}", nonempty=False),
                )
                for key, item in raw_variables.items()
            )
        )
        return cls(
            workspace=_string(data.get("workspace"), f"{path}.workspace"),
            directories=_string_tuple(
                data.get("directories", []), f"{path}.directories", allow_empty=True
            ),
            variables=variables,
            context=tuple(
                EnvironmentContext.from_dict(item, f"{path}.context[{index}]")
                for index, item in enumerate(_array(data.get("context", []), f"{path}.context"))
            ),
            tools=tuple(
                EnvironmentTool.from_dict(item, f"{path}.tools[{index}]")
                for index, item in enumerate(_array(data.get("tools", []), f"{path}.tools"))
            ),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {
            "workspace": self.workspace,
            "directories": list(self.directories),
            "variables": dict(self.variables),
            "context": [item.to_dict() for item in self.context],
            "tools": [item.to_dict() for item in self.tools],
        }


@dataclass(frozen=True)
class ClaudeOverride:
    model: str | None = None
    tools: tuple[str, ...] = ()
    agent_file: str | None = None
    isolation: str | None = None

    def __post_init__(self) -> None:
        if self.model is not None:
            _string(self.model, "provider_overrides.claude.model")
        if self.agent_file is not None:
            _relative_path(self.agent_file, "provider_overrides.claude.agent_file")
        if self.isolation is not None and self.isolation != "worktree":
            raise ContractError("provider_overrides.claude.isolation must be worktree")
        for index, tool in enumerate(self.tools):
            _string(tool, f"provider_overrides.claude.tools[{index}]")

    @classmethod
    def from_dict(cls, value: object, path: str) -> ClaudeOverride:
        data = _object(value, path)
        _reject_unknown(data, {"model", "tools", "agent_file", "isolation"}, path)
        result = cls(
            model=_optional_string(data.get("model"), f"{path}.model"),
            tools=_string_tuple(data.get("tools", []), f"{path}.tools", allow_empty=True),
            agent_file=_optional_string(data.get("agent_file"), f"{path}.agent_file"),
            isolation=_optional_string(data.get("isolation"), f"{path}.isolation"),
        )
        if (
            result.model is None
            and not result.tools
            and result.agent_file is None
            and result.isolation is None
        ):
            raise ContractError(f"{path} must contain at least one override")
        return result

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {}
        if self.model is not None:
            result["model"] = self.model
        if self.tools:
            result["tools"] = list(self.tools)
        if self.agent_file is not None:
            result["agent_file"] = self.agent_file
        if self.isolation is not None:
            result["isolation"] = self.isolation
        return result


@dataclass(frozen=True)
class CodexOverride:
    model: str | None = None
    reasoning_effort: ReasoningEffort | None = None
    sandbox_mode: str | None = None

    def __post_init__(self) -> None:
        if self.model is not None:
            _string(self.model, "provider_overrides.codex.model")
        if self.sandbox_mode is not None and self.sandbox_mode not in {
            "read-only",
            "workspace-write",
        }:
            raise ContractError("provider_overrides.codex.sandbox_mode is invalid")

    @classmethod
    def from_dict(cls, value: object, path: str) -> CodexOverride:
        data = _object(value, path)
        _reject_unknown(data, {"model", "reasoning_effort", "sandbox_mode"}, path)
        effort_value = data.get("reasoning_effort")
        result = cls(
            model=_optional_string(data.get("model"), f"{path}.model"),
            reasoning_effort=(
                None
                if effort_value is None
                else ReasoningEffort(
                    _enum_member(ReasoningEffort, effort_value, f"{path}.reasoning_effort").value
                )
            ),
            sandbox_mode=_optional_string(data.get("sandbox_mode"), f"{path}.sandbox_mode"),
        )
        if result.model is None and result.reasoning_effort is None and result.sandbox_mode is None:
            raise ContractError(f"{path} must contain at least one override")
        return result

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {}
        if self.model is not None:
            result["model"] = self.model
        if self.reasoning_effort is not None:
            result["reasoning_effort"] = self.reasoning_effort.value
        if self.sandbox_mode is not None:
            result["sandbox_mode"] = self.sandbox_mode
        return result


@dataclass(frozen=True)
class ProviderOverrides:
    claude: ClaudeOverride | None = None
    codex: CodexOverride | None = None

    def __post_init__(self) -> None:
        if self.claude is None and self.codex is None:
            raise ContractError("provider_overrides must contain at least one provider")

    @classmethod
    def from_dict(cls, value: object, path: str) -> ProviderOverrides:
        data = _object(value, path)
        _reject_unknown(data, {"claude", "codex"}, path)
        return cls(
            claude=(
                None
                if data.get("claude") is None
                else ClaudeOverride.from_dict(data.get("claude"), f"{path}.claude")
            ),
            codex=(
                None
                if data.get("codex") is None
                else CodexOverride.from_dict(data.get("codex"), f"{path}.codex")
            ),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {}
        if self.claude is not None:
            result["claude"] = self.claude.to_dict()
        if self.codex is not None:
            result["codex"] = self.codex.to_dict()
        return result


@dataclass(frozen=True)
class Role:
    id: str
    purpose: str
    description: str
    file_ownership: FileOwnership
    capabilities: tuple[str, ...]
    reasoning: Reasoning
    active: bool = True
    goal_ref: str | None = None
    environment: Environment | None = None
    provider_overrides: ProviderOverrides | None = None
    onboarded_skills: tuple[OnboardedSkill, ...] = ()
    created: str | None = None

    def __post_init__(self) -> None:
        if not _ROLE_ID_PATTERN.fullmatch(self.id):
            raise ContractError("role.id must be lowercase kebab-case")
        _string(self.purpose, "role.purpose")
        _string(self.description, "role.description")
        if not self.capabilities:
            raise ContractError("role.capabilities must contain at least one capability")
        if len(self.capabilities) != len(set(self.capabilities)):
            raise ContractError("role.capabilities must not contain duplicates")
        for index, capability in enumerate(self.capabilities):
            if not re.fullmatch(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$", capability):
                raise ContractError(f"role.capabilities[{index}] is not a portable capability name")
        if self.goal_ref is not None:
            _relative_path(self.goal_ref, "role.goal_ref")
        skill_names = [skill.name for skill in self.onboarded_skills]
        if len(skill_names) != len(set(skill_names)):
            raise ContractError("role.onboarded_skills must have unique names")
        if self.created is not None:
            _string(self.created, "role.created")

    @classmethod
    def from_dict(cls, value: object, path: str) -> Role:
        data = _object(value, path)
        _reject_unknown(
            data,
            {
                "id",
                "purpose",
                "description",
                "file_ownership",
                "capabilities",
                "reasoning",
                "active",
                "goal_ref",
                "environment",
                "provider_overrides",
                "onboarded_skills",
                "created",
            },
            path,
        )
        return cls(
            id=_string(data.get("id"), f"{path}.id"),
            purpose=_string(data.get("purpose"), f"{path}.purpose"),
            description=_string(data.get("description"), f"{path}.description"),
            file_ownership=FileOwnership.from_dict(
                data.get("file_ownership"), f"{path}.file_ownership"
            ),
            capabilities=_string_tuple(data.get("capabilities"), f"{path}.capabilities"),
            reasoning=Reasoning.from_dict(data.get("reasoning"), f"{path}.reasoning"),
            active=_boolean(data.get("active", True), f"{path}.active"),
            goal_ref=_optional_string(data.get("goal_ref"), f"{path}.goal_ref"),
            environment=(
                None
                if data.get("environment") is None
                else Environment.from_dict(data.get("environment"), f"{path}.environment")
            ),
            provider_overrides=(
                None
                if data.get("provider_overrides") is None
                else ProviderOverrides.from_dict(
                    data.get("provider_overrides"), f"{path}.provider_overrides"
                )
            ),
            onboarded_skills=tuple(
                OnboardedSkill.from_dict(item, f"{path}.onboarded_skills[{index}]")
                for index, item in enumerate(
                    _array(data.get("onboarded_skills", []), f"{path}.onboarded_skills")
                )
            ),
            created=_optional_string(data.get("created"), f"{path}.created"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {
            "id": self.id,
            "purpose": self.purpose,
            "description": self.description,
            "file_ownership": self.file_ownership.to_dict(),
            "capabilities": list(self.capabilities),
            "reasoning": self.reasoning.to_dict(),
            "active": self.active,
        }
        if self.goal_ref is not None:
            result["goal_ref"] = self.goal_ref
        if self.environment is not None:
            result["environment"] = self.environment.to_dict()
        if self.provider_overrides is not None:
            result["provider_overrides"] = self.provider_overrides.to_dict()
        if self.onboarded_skills:
            result["onboarded_skills"] = [skill.to_dict() for skill in self.onboarded_skills]
        if self.created is not None:
            result["created"] = self.created
        return result


@dataclass(frozen=True)
class Roster:
    squad_goal_ref: str
    execution_mode: ExecutionMode
    roles: tuple[Role, ...]
    created: str | None = None
    schema_version: int = field(default=2, init=False)

    def __post_init__(self) -> None:
        _relative_path(self.squad_goal_ref, "roster.squad_goal_ref")
        role_ids = [role.id for role in self.roles]
        if len(role_ids) != len(set(role_ids)):
            raise ContractError("roster.roles must have unique ids")
        if self.created is not None:
            _string(self.created, "roster.created")

    def active_roles(self) -> tuple[Role, ...]:
        """Return the roster's active roles, in declared order.

        Over-cap rosters (more than MAX_ACTIVE_ROLES active roles) are not
        rejected here — they are grandfathered. Callers that enforce the cap
        on new additions do so at the write boundary, not on load.
        """

        return tuple(role for role in self.roles if role.active)

    @classmethod
    def from_dict(cls, value: object) -> Roster:
        data = _object(value, "roster")
        _reject_unknown(
            data,
            {"schema_version", "squad_goal_ref", "execution_mode", "created", "roles"},
            "roster",
        )
        if data.get("schema_version") != 2:
            raise ContractError("roster.schema_version must be 2")
        return cls(
            squad_goal_ref=_string(data.get("squad_goal_ref"), "roster.squad_goal_ref"),
            execution_mode=ExecutionMode(
                _enum_member(
                    ExecutionMode, data.get("execution_mode"), "roster.execution_mode"
                ).value
            ),
            roles=tuple(
                Role.from_dict(item, f"roster.roles[{index}]")
                for index, item in enumerate(_array(data.get("roles"), "roster.roles"))
            ),
            created=_optional_string(data.get("created"), "roster.created"),
        )

    def to_dict(self) -> dict[str, JsonValue]:
        result: dict[str, JsonValue] = {
            "schema_version": self.schema_version,
            "squad_goal_ref": self.squad_goal_ref,
            "execution_mode": self.execution_mode.value,
            "roles": [role.to_dict() for role in self.roles],
        }
        if self.created is not None:
            result["created"] = self.created
        return result


def normalize_capabilities(capabilities: Sequence[str]) -> tuple[str, ...]:
    """Return stable set-like ordering for compiler inputs."""

    return sorted_unique(capabilities)

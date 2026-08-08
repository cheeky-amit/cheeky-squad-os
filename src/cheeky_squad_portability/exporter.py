"""Safe, deterministic planning and application of portable squad exports."""

from __future__ import annotations

import hmac
import json
import os
import re
import shutil
import stat
import tempfile
import tomllib
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from cheeky_squad_portability.contracts import (
    Destination,
    Provider,
    Roster,
    SquadManifest,
)
from cheeky_squad_portability.json_io import canonical_json_bytes, pretty_json, sha256_bytes
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.plan import ExportPlan, build_export_plan
from cheeky_squad_portability.receipt import (
    ExportReceipt,
    ReceiptError,
    ReceiptFile,
    normalize_relative_path,
)

Compiler = Callable[[SquadManifest, Roster], Mapping[str, bytes]]
PluginCompiler = Callable[[SquadManifest, Roster, Mapping[str, bytes]], Mapping[str, bytes]]
FaultHook = Callable[[str, str], None]

_PLACEHOLDERS = (
    re.compile(r"\{\{[^{}]+\}\}"),
    re.compile(r"@@[A-Z0-9_]+@@"),
    re.compile(r"__CHEEKY_[A-Z0-9_]+__"),
    re.compile(r"TODO:\s*replace", re.IGNORECASE),
)
_TEXT_SUFFIXES = {
    ".json",
    ".md",
    ".py",
    ".sh",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}
_PRIVATE_COMPONENTS = {
    "engagement-records",
    "engagements",
    "private-state",
    "secrets",
    "workspaces",
}
_MIT_LICENSE = b"""MIT License

Copyright (c) 2026 amit-cheeky

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


class ExportError(RuntimeError):
    """An export cannot be planned, applied, validated, or removed safely."""


@dataclass(frozen=True)
class ProviderCompilers:
    """Provider renderers injected at the portability boundary."""

    claude_agents: Compiler | None = None
    claude_plugin: PluginCompiler | None = None
    codex_agents: Compiler | None = None
    codex_skills: Compiler | None = None
    codex_plugin: PluginCompiler | None = None


@dataclass(frozen=True)
class PreparedWrite:
    path: str
    content: bytes
    executable: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", _relative(self.path, "write path"))
        if not isinstance(self.content, bytes):
            raise ExportError("prepared write content must be bytes")


@dataclass(frozen=True)
class PathState:
    path: str
    kind: str
    sha256: str | None = None

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", _relative(self.path, "state path"))
        if self.kind not in {"missing", "file"}:
            raise ExportError("path state kind must be missing or file")
        if (self.kind == "file") != (self.sha256 is not None):
            raise ExportError("file path states require a hash and missing states cannot have one")


@dataclass(frozen=True)
class PreparedExport:
    """Exact bytes, preconditions, and public preview for one apply operation."""

    plan: ExportPlan
    writes: tuple[PreparedWrite, ...]
    preconditions: tuple[PathState, ...]
    receipt_path: str | None
    session_prompt: str | None = None
    home_root: str | None = None

    def write_map(self) -> dict[str, bytes]:
        return {item.path: item.content for item in self.writes}


@dataclass(frozen=True)
class ApplyResult:
    plan_id: str
    written: tuple[str, ...]
    deleted: tuple[str, ...]
    session_prompt: str | None = None


@dataclass(frozen=True)
class ValidationReport:
    squad_id: str
    destination: Destination
    checked_files: tuple[str, ...]


@dataclass(frozen=True)
class UninstallResult:
    deleted: tuple[str, ...]
    preserved_modified: tuple[str, ...]
    receipt_retained: bool


def squad_namespace(squad_id: str) -> str:
    """Return the stable namespace used for user-level discovery artifacts."""

    return squad_id.replace(".", "-")


def _relative(value: str, label: str) -> str:
    try:
        return normalize_relative_path(value, label=label)
    except ReceiptError as error:
        raise ExportError(str(error)) from error


def _private_path(path: str) -> bool:
    parts = PurePosixPath(path).parts
    name = parts[-1]
    return (
        path == ".squad/partner.md"
        or name.startswith(".env")
        or any(part.lower() in _PRIVATE_COMPONENTS for part in parts)
    )


def _validate_path_set(paths: Iterable[str]) -> tuple[str, ...]:
    normalized = tuple(sorted(_relative(path, "output path") for path in paths))
    if len(normalized) != len(set(normalized)):
        raise ExportError("output paths must not contain duplicates")
    for index, path in enumerate(normalized):
        if _private_path(path):
            raise ExportError(f"private or live state is excluded from exports: {path}")
        prefix = f"{path}/"
        if any(other.startswith(prefix) for other in normalized[index + 1 :]):
            raise ExportError(f"output paths cannot contain file/directory ambiguity: {path}")
    return normalized


def _merge_outputs(target: dict[str, bytes], rendered: Mapping[str, bytes]) -> None:
    if not isinstance(rendered, Mapping):
        raise ExportError("provider compiler output must be a path-to-bytes mapping")
    for raw_path, content in rendered.items():
        if not isinstance(raw_path, str) or not isinstance(content, bytes):
            raise ExportError("provider compiler output must map string paths to bytes")
        path = _relative(raw_path, "compiler output path")
        if path in target:
            raise ExportError(f"multiple generated artifacts collide at {path}")
        target[path] = content


def _add_engine_output(target: dict[str, bytes], path: str, content: bytes) -> None:
    if path in target:
        if target[path] == content:
            return
        raise ExportError(f"provider output collides with engine-owned artifact at {path}")
    target[path] = content


def _mount_agent_outputs(
    target: dict[str, bytes], provider: Provider, rendered: Mapping[str, bytes]
) -> None:
    mounted: dict[str, bytes] = {}
    for path, content in rendered.items():
        relative = _relative(path, "provider-relative agent path")
        if provider is Provider.CLAUDE and relative.startswith("agents/"):
            destination = f".claude/{relative}"
        elif provider is Provider.CODEX and relative.startswith("agents/"):
            destination = f".codex/{relative}"
        elif provider is Provider.CODEX and relative.startswith("skills/"):
            destination = f".agents/{relative}"
        else:
            raise ExportError(f"unexpected {provider.value} project/user compiler path: {relative}")
        mounted[destination] = content
    _merge_outputs(target, mounted)


def _json_bytes(value: object) -> bytes:
    return pretty_json(value).encode("utf-8")  # type: ignore[arg-type]


def _canonical_paths(destination: Destination, namespace: str) -> tuple[str, str, str]:
    if destination is Destination.USER:
        prefix = f".squad/squads/{namespace}"
        return (
            f"{prefix}/manifest.json",
            f"{prefix}/roster.json",
            f".squad/receipts/{namespace}.json",
        )
    return ".squad/manifest.json", ".squad/roster.json", ".squad/export-receipt.json"


def _activation_bytes(manifest: SquadManifest) -> bytes:
    providers = ", ".join(sorted(item.value for item in manifest.providers))
    return (
        "# Activate this portable squad\n\n"
        "This directory is a generated, vendored snapshot. It does not require the "
        "squad generator at runtime. Generation does not install or enable it.\n\n"
        f"Included providers: {providers}.\n\n"
        "- Claude: add this directory as a plugin and explicitly enable it.\n"
        "- Codex: add this directory as a plugin. Packaged custom roles are dispatched "
        "from the vendored prompts because plugin custom-agent discovery is not assumed.\n"
    ).encode()


def _session_prompt(manifest: SquadManifest, roster: Roster) -> str:
    active_roles = [role.to_dict() for role in roster.roles if role.active]
    payload = pretty_json(
        {
            "manifest": manifest.to_dict(),
            "roles": active_roles,
            "dispatch_policy": (
                "Run mutating roles sequentially. File ownership is instructional; "
                "respect it, but do not claim mechanical enforcement."
            ),
        }
    )
    return (
        "Use the following vendored squad definition for this session only. Do not create "
        "agent-discovery or global files.\n\n"
        f"```json\n{payload}```"
    )


def _source_hash(
    manifest: SquadManifest,
    roster: Roster,
    desired_files: Mapping[str, bytes],
    session_prompt: str | None,
) -> str:
    return sha256_bytes(
        canonical_json_bytes(
            {
                "manifest": manifest.to_dict(),
                "roster": roster.to_dict(),
                "files": {
                    path: sha256_bytes(content) for path, content in sorted(desired_files.items())
                },
                "session_prompt_sha256": (
                    None if session_prompt is None else sha256_bytes(session_prompt.encode())
                ),
            }
        )
    )


def _target_path(
    destination: Destination,
    target_root: Path | None,
    home: Path | None,
) -> Path | None:
    if destination is Destination.SESSION:
        if target_root is not None:
            raise ExportError("session exports do not accept a filesystem target")
        return None
    if target_root is None:
        raise ExportError(f"{destination.value} exports require a target root")
    if not target_root.is_absolute() or ".." in target_root.parts or "~" in str(target_root):
        raise ExportError("target root must be an explicit absolute path without traversal")
    _reject_symlink_components(target_root)
    resolved = target_root.resolve(strict=False)
    if resolved != target_root:
        raise ExportError("target root must not contain symlink components")
    if resolved == Path(resolved.anchor):
        raise ExportError("filesystem roots cannot be export targets")

    resolved_home = None if home is None else home.resolve(strict=False)
    system_home = Path.home().resolve(strict=False)
    if destination is Destination.USER:
        if home is None or not home.is_absolute():
            raise ExportError("user exports require an explicit absolute home directory")
        _reject_symlink_components(home)
        if resolved != resolved_home:
            raise ExportError("user export target must be exactly the passed home directory")
    elif resolved == system_home or (resolved_home is not None and resolved == resolved_home):
        raise ExportError("project and plugin exports cannot target a home directory")

    if not resolved.exists() or not resolved.is_dir():
        raise ExportError("export target must be an existing directory")
    if destination is Destination.PROJECT and not (resolved / ".git").exists():
        raise ExportError("project export target must be a selected Git repository root")
    return resolved


def _reject_symlink_components(path: Path) -> None:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            return
        if stat.S_ISLNK(mode):
            raise ExportError(f"symlink path components are not allowed: {current}")


def _capture_state(root: Path, relative_path: str) -> PathState:
    path = _relative(relative_path, "filesystem path")
    candidate = root.joinpath(*PurePosixPath(path).parts)
    _reject_symlink_components(candidate)
    try:
        mode = candidate.lstat().st_mode
    except FileNotFoundError:
        return PathState(path=path, kind="missing")
    if stat.S_ISREG(mode):
        return PathState(path=path, kind="file", sha256=sha256_bytes(candidate.read_bytes()))
    raise ExportError(f"export paths must resolve to regular files or be absent: {path}")


def _validate_user_namespaces(paths: Iterable[str], namespace: str) -> None:
    canonical_prefix = f".squad/squads/{namespace}/"
    receipt = f".squad/receipts/{namespace}.json"
    direct_roots = {
        ".agents/skills": 2,
        ".claude/agents": 2,
        ".claude/skills": 2,
        ".codex/agents": 2,
        ".codex/skills": 2,
    }
    expected = f"{namespace}--"
    for path in paths:
        if path.startswith(canonical_prefix) or path == receipt:
            continue
        parts = PurePosixPath(path).parts
        matched = False
        for root, index in direct_roots.items():
            if path.startswith(f"{root}/") and len(parts) > index:
                matched = parts[index].startswith(expected)
                break
        if not matched:
            raise ExportError(f"user artifact is not namespaced for {namespace}: {path}")


def _validate_text(path: str, content: bytes, *, plugin: bool) -> None:
    if PurePosixPath(path).suffix.lower() not in _TEXT_SUFFIXES:
        return
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ExportError(f"text artifact is not UTF-8: {path}") from error
    authored_template = (
        "templates" in PurePosixPath(path).parts
        or path.startswith("skills/")
        or path.startswith("runtime/skills/")
        or path.startswith("shared/runtime/skills/")
    )
    if not authored_template and any(pattern.search(text) for pattern in _PLACEHOLDERS):
        raise ExportError(f"unresolved placeholder in generated artifact: {path}")
    imports_generator = (
        "import cheeky_squad_portability" in text or "from cheeky_squad_portability" in text
    )
    if plugin and PurePosixPath(path).suffix.lower() in {".py", ".sh"} and imports_generator:
        raise ExportError(f"plugin runtime depends on the generator package: {path}")
    try:
        if path.endswith(".json"):
            json.loads(text)
        elif path.endswith(".toml"):
            tomllib.loads(text)
    except (json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        raise ExportError(f"generated artifact is malformed: {path}: {error}") from error


def _validate_artifacts(
    manifest: SquadManifest,
    destination: Destination,
    files: Mapping[str, bytes],
    namespace: str,
) -> None:
    paths = _validate_path_set(files)
    if destination is Destination.USER:
        _validate_user_namespaces(paths, namespace)
    for path in paths:
        _validate_text(path, files[path], plugin=destination is Destination.PLUGIN)

    if Provider.CLAUDE in manifest.providers:
        if destination is Destination.PLUGIN:
            required = ".claude-plugin/plugin.json"
            if required not in files:
                raise ExportError(f"Claude plugin output is missing {required}")
            _validate_provider_manifest(required, files[required], manifest.export_version)
        elif destination is not Destination.SESSION and not any(
            path.startswith(".claude/agents/") and path.endswith(".md") for path in paths
        ):
            raise ExportError("Claude agent output must include a namespaced Markdown agent")
        claude_agents = (
            path
            for path in paths
            if path.endswith(".md") and path.startswith(("agents/", ".claude/agents/"))
        )
        for path in claude_agents:
            _validate_claude_agent(path, files[path])
    if Provider.CODEX in manifest.providers:
        if destination is Destination.PLUGIN:
            required = ".codex-plugin/plugin.json"
            if required not in files:
                raise ExportError(f"Codex plugin output is missing {required}")
            _validate_provider_manifest(required, files[required], manifest.export_version)
        elif destination is not Destination.SESSION and not any(
            path.startswith(".codex/agents/") and path.endswith(".toml") for path in paths
        ):
            raise ExportError("Codex agent output must include a namespaced TOML agent")
        for path in (
            path for path in paths if path.startswith(".codex/agents/") and path.endswith(".toml")
        ):
            _validate_codex_agent(path, files[path])

    if destination is Destination.PLUGIN:
        required_common = {
            ".squad/manifest.json",
            ".squad/roster.json",
            "ACTIVATION.md",
            "LICENSE",
            "shared/manifest.json",
            "shared/roster.json",
        }
        missing = sorted(required_common - set(paths))
        if missing:
            raise ExportError(f"plugin output is missing required artifacts: {', '.join(missing)}")


def _validate_provider_manifest(path: str, content: bytes, export_version: str) -> None:
    value = json.loads(content)
    if not isinstance(value, dict):
        raise ExportError(f"provider manifest must be a JSON object: {path}")
    if not isinstance(value.get("name"), str) or not value["name"]:
        raise ExportError(f"provider manifest is missing name: {path}")
    if value.get("version") != export_version:
        raise ExportError(f"provider manifest version does not match export version: {path}")


def _validate_claude_agent(path: str, content: bytes) -> None:
    text = content.decode("utf-8")
    if not text.startswith("---\n"):
        raise ExportError(f"Claude agent is missing frontmatter: {path}")
    try:
        frontmatter = text.split("---\n", 2)[1]
    except IndexError as error:
        raise ExportError(f"Claude agent frontmatter is unterminated: {path}") from error
    for field in ("name:", "description:"):
        if not any(line.startswith(field) for line in frontmatter.splitlines()):
            raise ExportError(f"Claude agent frontmatter is missing {field[:-1]}: {path}")


def _validate_codex_agent(path: str, content: bytes) -> None:
    value = tomllib.loads(content.decode("utf-8"))
    for field in ("name", "description", "developer_instructions"):
        if not isinstance(value.get(field), str) or not value[field]:
            raise ExportError(f"Codex agent TOML is missing {field}: {path}")


def _render_desired_files(
    manifest: SquadManifest,
    roster: Roster,
    compilers: ProviderCompilers,
    vendored_files: Mapping[str, bytes],
    license_bytes: bytes,
) -> tuple[dict[str, bytes], str, str, str]:
    namespace = squad_namespace(manifest.squad.id)
    manifest_path, roster_path, receipt_path = _canonical_paths(manifest.destination, namespace)
    rendered: dict[str, bytes] = {}
    plugin_runtime = dict(vendored_files)
    if "LICENSE" in plugin_runtime and plugin_runtime["LICENSE"] != license_bytes:
        raise ExportError("vendored LICENSE conflicts with the selected export license")
    plugin_runtime.setdefault("LICENSE", license_bytes)
    for provider in sorted(manifest.providers, key=lambda item: item.value):
        if manifest.destination is Destination.PLUGIN:
            plugin_compiler = (
                compilers.claude_plugin if provider is Provider.CLAUDE else compilers.codex_plugin
            )
            if plugin_compiler is None:
                raise ExportError(f"no {provider.value} plugin compiler was provided")
            _merge_outputs(rendered, plugin_compiler(manifest, roster, plugin_runtime))
            continue
        agent_compiler = (
            compilers.claude_agents if provider is Provider.CLAUDE else compilers.codex_agents
        )
        if agent_compiler is None:
            raise ExportError(f"no {provider.value} agent compiler was provided")
        _mount_agent_outputs(rendered, provider, agent_compiler(manifest, roster))
        if provider is Provider.CODEX and compilers.codex_skills is not None:
            _mount_agent_outputs(
                rendered,
                provider,
                compilers.codex_skills(manifest, roster),
            )

    manifest_bytes = _json_bytes(manifest.to_dict())
    roster_bytes = _json_bytes(roster.to_dict())
    _add_engine_output(rendered, manifest_path, manifest_bytes)
    _add_engine_output(rendered, roster_path, roster_bytes)
    if manifest.destination is Destination.PLUGIN:
        for path, content in {
            "ACTIVATION.md": _activation_bytes(manifest),
            "LICENSE": license_bytes,
            "shared/manifest.json": manifest_bytes,
            "shared/roster.json": roster_bytes,
        }.items():
            _add_engine_output(rendered, path, content)
        for path, content in sorted(vendored_files.items()):
            runtime_path = _relative(path, "vendored runtime path")
            shared_path = (
                runtime_path
                if runtime_path.startswith("shared/")
                else f"shared/runtime/{runtime_path}"
            )
            _add_engine_output(rendered, shared_path, content)
    else:
        _merge_outputs(rendered, vendored_files)
    if receipt_path in rendered:
        raise ExportError("provider output cannot replace the engine-owned export receipt")
    _validate_artifacts(manifest, manifest.destination, rendered, namespace)
    return rendered, manifest_path, roster_path, receipt_path


def _load_receipt(
    root: Path,
    receipt_path: str,
    manifest: SquadManifest | None = None,
    *,
    squad_id: str | None = None,
    destination: Destination | None = None,
) -> tuple[ExportReceipt | None, PathState]:
    state = _capture_state(root, receipt_path)
    if state.kind == "missing":
        return None, state
    try:
        receipt = ExportReceipt.from_bytes(
            root.joinpath(*PurePosixPath(receipt_path).parts).read_bytes()
        )
    except ReceiptError as error:
        raise ExportError(f"existing export receipt is invalid: {error}") from error
    expected_squad = manifest.squad.id if manifest is not None else squad_id
    expected_destination = manifest.destination if manifest is not None else destination
    if receipt.squad_id != expected_squad or receipt.destination is not expected_destination:
        raise ExportError("existing receipt belongs to a different squad or destination")
    return receipt, state


def plan_export(
    *,
    manifest: SquadManifest,
    roster: Roster,
    compilers: ProviderCompilers | None = None,
    target_root: Path | None = None,
    home: Path | None = None,
    vendored_files: Mapping[str, bytes] | None = None,
    executable_paths: Iterable[str] = (),
    license_bytes: bytes = _MIT_LICENSE,
) -> PreparedExport:
    """Validate inputs and return the exact, deterministic write/delete preview."""

    if manifest.execution_mode is not roster.execution_mode:
        raise ExportError("manifest and roster execution modes must match")
    root = _target_path(manifest.destination, target_root, home)
    selected_compilers = ProviderCompilers() if compilers is None else compilers
    vendored = {} if vendored_files is None else dict(vendored_files)

    if manifest.destination is Destination.SESSION:
        prompt = _session_prompt(manifest, roster)
        source_hash = _source_hash(manifest, roster, {}, prompt)
        plan = build_export_plan(
            manifest=manifest,
            target_root=f"session:{manifest.squad.id}",
            source_sha256=source_hash,
            writes={},
        )
        return PreparedExport(
            plan=plan,
            writes=(),
            preconditions=(),
            receipt_path=None,
            session_prompt=prompt,
            home_root=None,
        )

    assert root is not None
    desired, _, _, receipt_path = _render_desired_files(
        manifest, roster, selected_compilers, vendored, license_bytes
    )
    requested_executables = {_relative(path, "executable path") for path in executable_paths}
    executable: set[str] = set()
    for requested in requested_executables:
        matches = {path for path in desired if path == requested or path.endswith(f"/{requested}")}
        if not matches:
            raise ExportError("executable paths must be generated output files")
        executable.update(matches)
    source_hash = _source_hash(manifest, roster, desired, None)
    old_receipt, receipt_state = _load_receipt(root, receipt_path, manifest)
    old_files = {} if old_receipt is None else {item.path: item for item in old_receipt.files}

    writes: dict[str, bytes] = {}
    deletes: list[str] = []
    preconditions: dict[str, PathState] = {receipt_path: receipt_state}
    for path, content in sorted(desired.items()):
        state = _capture_state(root, path)
        preconditions[path] = state
        old = old_files.get(path)
        desired_hash = sha256_bytes(content)
        if state.kind == "file":
            if old is None:
                raise ExportError(f"unowned file collision at {path}")
            if state.sha256 != old.sha256:
                raise ExportError(f"receipt-owned file was modified and cannot be replaced: {path}")
            if state.sha256 != desired_hash:
                writes[path] = content
        else:
            writes[path] = content

    for path, old in sorted(old_files.items()):
        if path in desired:
            continue
        if _private_path(path):
            raise ExportError(f"receipt cannot authorize private or live state: {path}")
        state = _capture_state(root, path)
        preconditions[path] = state
        if state.kind == "file" and state.sha256 == old.sha256:
            deletes.append(path)

    receipt = ExportReceipt(
        squad_id=manifest.squad.id,
        destination=manifest.destination,
        export_version=manifest.export_version,
        source_sha256=source_hash,
        files=tuple(
            ReceiptFile(
                path=path,
                sha256=sha256_bytes(content),
                executable=path in executable,
            )
            for path, content in sorted(desired.items())
        ),
    )
    receipt_bytes = receipt.to_bytes()
    if receipt_state.kind == "missing" or receipt_state.sha256 != sha256_bytes(receipt_bytes):
        writes[receipt_path] = receipt_bytes

    all_paths = _validate_path_set((*writes, *deletes))
    prepared_writes = tuple(
        PreparedWrite(path=path, content=writes[path], executable=path in executable)
        for path in sorted(writes)
    )
    plan = build_export_plan(
        manifest=manifest,
        target_root=str(root),
        source_sha256=source_hash,
        writes=writes,
        deletes=deletes,
        executable_paths=(item.path for item in prepared_writes if item.executable),
    )
    if set(all_paths) != {item.path for item in (*plan.writes, *plan.deletes)}:
        raise ExportError("internal export plan path mismatch")
    return PreparedExport(
        plan=plan,
        writes=prepared_writes,
        preconditions=tuple(preconditions[path] for path in sorted(preconditions)),
        receipt_path=receipt_path,
        home_root=None if home is None else str(home.resolve(strict=False)),
    )


def validate_prepared_export(prepared: PreparedExport) -> ValidationReport:
    """Verify exact write bytes still match the content-addressed public plan."""

    write_map = prepared.write_map()
    if len(write_map) != len(prepared.writes):
        raise ExportError("prepared export contains duplicate write paths")
    rebuilt = build_export_plan(
        manifest=prepared.plan.manifest,
        target_root=prepared.plan.target_root,
        source_sha256=prepared.plan.source_sha256,
        writes=write_map,
        deletes=(item.path for item in prepared.plan.deletes),
        executable_paths=(item.path for item in prepared.writes if item.executable),
    )
    if rebuilt != prepared.plan:
        raise ExportError("prepared bytes do not match the confirmed export plan")
    return ValidationReport(
        squad_id=prepared.plan.manifest.squad.id,
        destination=prepared.plan.manifest.destination,
        checked_files=tuple(sorted(write_map)),
    )


def _assert_preconditions(root: Path, states: Iterable[PathState]) -> None:
    for expected in states:
        if _capture_state(root, expected.path) != expected:
            raise ExportError(
                f"filesystem changed after preview; plan again before applying: {expected.path}"
            )


def _remove_empty_parents(root: Path, paths: Iterable[str]) -> None:
    for relative in sorted(paths, reverse=True):
        parent = root.joinpath(*PurePosixPath(relative).parts).parent
        while parent != root:
            try:
                parent.rmdir()
            except OSError:
                break
            parent = parent.parent


def _atomic_apply(
    root: Path,
    writes: Mapping[str, bytes],
    deletes: Iterable[str],
    executable_paths: set[str],
    fault_hook: FaultHook | None,
) -> None:
    paths = _validate_path_set((*writes, *deletes))
    transaction = Path(tempfile.mkdtemp(prefix=".squad-export-txn-", dir=root))
    staging = transaction / "staging"
    backup = transaction / "backup"
    installed: list[str] = []
    backed_up: list[str] = []
    try:
        for path, content in sorted(writes.items()):
            staged = staging.joinpath(*PurePosixPath(path).parts)
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(content)
            staged.chmod(0o755 if path in executable_paths else 0o644)

        for path in paths:
            target = root.joinpath(*PurePosixPath(path).parts)
            _reject_symlink_components(target)
            if target.exists():
                if not target.is_file():
                    raise ExportError(f"transaction target is not a regular file: {path}")
                saved = backup.joinpath(*PurePosixPath(path).parts)
                saved.parent.mkdir(parents=True, exist_ok=True)
                os.replace(target, saved)
                backed_up.append(path)
                if fault_hook is not None:
                    fault_hook("backed_up", path)

        for path, _content in sorted(writes.items()):
            target = root.joinpath(*PurePosixPath(path).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            _reject_symlink_components(target)
            staged = staging.joinpath(*PurePosixPath(path).parts)
            os.replace(staged, target)
            target.chmod(0o755 if path in executable_paths else 0o644)
            installed.append(path)
            if fault_hook is not None:
                fault_hook("written", path)
        if fault_hook is not None:
            fault_hook("committed", "")
    except BaseException:
        for path in reversed(installed):
            target = root.joinpath(*PurePosixPath(path).parts)
            if target.exists() and target.is_file() and not target.is_symlink():
                target.unlink()
        for path in reversed(backed_up):
            saved = backup.joinpath(*PurePosixPath(path).parts)
            if saved.exists():
                target = root.joinpath(*PurePosixPath(path).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(saved, target)
        _remove_empty_parents(root, paths)
        shutil.rmtree(transaction, ignore_errors=True)
        raise
    shutil.rmtree(transaction)
    _remove_empty_parents(root, deletes)


def apply_export(
    prepared: PreparedExport,
    *,
    confirmed_plan_id: str,
    global_write_confirmed: bool = False,
    fault_hook: FaultHook | None = None,
) -> ApplyResult:
    """Apply only the exact confirmed preview, with rollback on any failure."""

    validate_prepared_export(prepared)
    if not hmac.compare_digest(confirmed_plan_id, prepared.plan.plan_id):
        raise ExportError("confirmed plan ID does not match the prepared export")
    destination = prepared.plan.manifest.destination
    if destination is Destination.USER and not global_write_confirmed:
        raise ExportError("user exports require separate explicit global-write confirmation")
    if destination is Destination.SESSION:
        return ApplyResult(
            plan_id=prepared.plan.plan_id,
            written=(),
            deleted=(),
            session_prompt=prepared.session_prompt,
        )

    root = _target_path(
        destination,
        Path(prepared.plan.target_root),
        None if prepared.home_root is None else Path(prepared.home_root),
    )
    assert root is not None
    _assert_preconditions(root, prepared.preconditions)
    writes = prepared.write_map()
    deletes = tuple(item.path for item in prepared.plan.deletes)
    executables = {item.path for item in prepared.writes if item.executable}
    _atomic_apply(root, writes, deletes, executables, fault_hook)
    return ApplyResult(
        plan_id=prepared.plan.plan_id,
        written=tuple(sorted(writes)),
        deleted=tuple(sorted(deletes)),
    )


def _installed_common_paths(destination: Destination, squad_id: str) -> tuple[str, str, str]:
    return _canonical_paths(destination, squad_namespace(squad_id))


def validate_installed_export(
    *,
    target_root: Path,
    destination: Destination,
    squad_id: str,
    home: Path | None = None,
) -> ValidationReport:
    """Validate receipt hashes, canonical contracts, placeholders, and provider artifacts."""

    root = _target_path(destination, target_root, home)
    if root is None:
        raise ExportError("session exports have no installed files to validate")
    manifest_path, roster_path, receipt_path = _installed_common_paths(destination, squad_id)
    receipt, _ = _load_receipt(root, receipt_path, squad_id=squad_id, destination=destination)
    if receipt is None:
        raise ExportError("installed export receipt is missing")
    files: dict[str, bytes] = {}
    for item in receipt.files:
        state = _capture_state(root, item.path)
        if state.kind != "file" or state.sha256 != item.sha256:
            raise ExportError(f"installed artifact does not match its receipt: {item.path}")
        content = root.joinpath(*PurePosixPath(item.path).parts).read_bytes()
        files[item.path] = content
        expected_mode = 0o111 if item.executable else 0
        has_execute = root.joinpath(*PurePosixPath(item.path).parts).stat().st_mode & 0o111
        if bool(has_execute) != bool(expected_mode):
            raise ExportError(f"installed artifact mode does not match its receipt: {item.path}")

    if manifest_path not in files or roster_path not in files:
        raise ExportError("installed export is missing canonical manifest or roster")
    try:
        manifest = SquadManifest.from_dict(json.loads(files[manifest_path]))
        roster = load_roster(json.loads(files[roster_path]))
    except (ValueError, TypeError, UnicodeDecodeError) as error:
        raise ExportError(f"installed canonical contracts are invalid: {error}") from error
    if manifest.squad.id != squad_id or manifest.destination is not destination:
        raise ExportError("installed manifest does not match the requested squad and destination")
    if manifest.execution_mode is not roster.execution_mode:
        raise ExportError("installed manifest and roster execution modes do not match")
    _validate_artifacts(manifest, destination, files, squad_namespace(squad_id))
    return ValidationReport(
        squad_id=squad_id,
        destination=destination,
        checked_files=tuple(sorted(files)),
    )


def uninstall_export(
    *,
    target_root: Path,
    destination: Destination,
    squad_id: str,
    confirmed: bool,
    home: Path | None = None,
    global_write_confirmed: bool = False,
    fault_hook: FaultHook | None = None,
) -> UninstallResult:
    """Remove only unmodified receipt-owned files and retain modified entries."""

    if not confirmed:
        raise ExportError("uninstall requires explicit confirmation")
    if destination is Destination.SESSION:
        raise ExportError("session exports create nothing to uninstall")
    if destination is Destination.USER and not global_write_confirmed:
        raise ExportError("user uninstall requires separate explicit global-write confirmation")
    root = _target_path(destination, target_root, home)
    assert root is not None
    _, _, receipt_path = _installed_common_paths(destination, squad_id)
    receipt, receipt_state = _load_receipt(
        root, receipt_path, squad_id=squad_id, destination=destination
    )
    if receipt is None:
        raise ExportError("export receipt is missing; no files can be safely uninstalled")

    deletes: list[str] = []
    preserved: list[ReceiptFile] = []
    preconditions: list[PathState] = [receipt_state]
    for item in receipt.files:
        state = _capture_state(root, item.path)
        preconditions.append(state)
        if state.kind == "missing":
            continue
        if state.sha256 == item.sha256:
            deletes.append(item.path)
        else:
            preserved.append(item)

    writes: dict[str, bytes] = {}
    if preserved:
        reduced = ExportReceipt(
            squad_id=receipt.squad_id,
            destination=receipt.destination,
            export_version=receipt.export_version,
            source_sha256=receipt.source_sha256,
            files=tuple(preserved),
        )
        writes[receipt_path] = reduced.to_bytes()
    else:
        deletes.append(receipt_path)
    _assert_preconditions(root, preconditions)
    _atomic_apply(root, writes, deletes, set(), fault_hook)
    return UninstallResult(
        deleted=tuple(sorted(deletes)),
        preserved_modified=tuple(item.path for item in preserved),
        receipt_retained=bool(preserved),
    )

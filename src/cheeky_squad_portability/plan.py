"""Content-addressed export-plan contract used by preview and apply."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from pathlib import PurePosixPath

from cheeky_squad_portability.contracts import SquadManifest
from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.json_io import JsonValue, canonical_json_bytes, sha256_bytes


def _relative_path(value: str, label: str) -> str:
    path = PurePosixPath(value)
    if not value or value.startswith("/") or path.is_absolute() or ".." in path.parts:
        raise ContractError(f"{label} must be a relative path without traversal")
    normalized = path.as_posix()
    if normalized in {".", ""}:
        raise ContractError(f"{label} must identify a file")
    return normalized


@dataclass(frozen=True)
class WriteOperation:
    path: str
    sha256: str
    size: int
    executable: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", _relative_path(self.path, "write.path"))
        if len(self.sha256) != 64 or any(char not in "0123456789abcdef" for char in self.sha256):
            raise ContractError("write.sha256 must be a lowercase SHA-256 digest")
        if self.size < 0:
            raise ContractError("write.size must be non-negative")

    def to_dict(self) -> dict[str, JsonValue]:
        return {
            "path": self.path,
            "sha256": self.sha256,
            "size": self.size,
            "executable": self.executable,
        }


@dataclass(frozen=True)
class DeleteOperation:
    path: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", _relative_path(self.path, "delete.path"))

    def to_dict(self) -> dict[str, JsonValue]:
        return {"path": self.path}


@dataclass(frozen=True)
class ExportPlan:
    manifest: SquadManifest
    target_root: str
    source_sha256: str
    writes: tuple[WriteOperation, ...]
    deletes: tuple[DeleteOperation, ...]
    plan_id: str = field(init=False)
    schema_version: int = field(default=1, init=False)

    def __post_init__(self) -> None:
        if not self.target_root:
            raise ContractError("target_root must be non-empty")
        if len(self.source_sha256) != 64 or any(
            char not in "0123456789abcdef" for char in self.source_sha256
        ):
            raise ContractError("source_sha256 must be a lowercase SHA-256 digest")
        paths = [operation.path for operation in (*self.writes, *self.deletes)]
        if len(paths) != len(set(paths)):
            raise ContractError("an export plan cannot write and/or delete the same path twice")
        payload = self._unsigned_dict()
        object.__setattr__(self, "plan_id", sha256_bytes(canonical_json_bytes(payload)))

    def _unsigned_dict(self) -> dict[str, JsonValue]:
        return {
            "schema_version": self.schema_version,
            "manifest": self.manifest.to_dict(),
            "target_root": self.target_root,
            "source_sha256": self.source_sha256,
            "writes": [item.to_dict() for item in sorted(self.writes, key=lambda item: item.path)],
            "deletes": [
                item.to_dict() for item in sorted(self.deletes, key=lambda item: item.path)
            ],
        }

    def to_dict(self) -> dict[str, JsonValue]:
        return {**self._unsigned_dict(), "plan_id": self.plan_id}


def build_export_plan(
    *,
    manifest: SquadManifest,
    target_root: str,
    source_sha256: str,
    writes: Mapping[str, bytes],
    deletes: Iterable[str] = (),
    executable_paths: Iterable[str] = (),
) -> ExportPlan:
    """Build a stable preview from exact intended bytes and delete paths."""

    executable = {_relative_path(path, "executable path") for path in executable_paths}
    unknown_executable = executable - set(writes)
    if unknown_executable:
        raise ContractError("executable paths must also be present in writes")
    write_operations = tuple(
        WriteOperation(
            path=path,
            sha256=sha256_bytes(content),
            size=len(content),
            executable=path in executable,
        )
        for path, content in sorted(writes.items())
    )
    delete_operations = tuple(DeleteOperation(path=path) for path in sorted(set(deletes)))
    return ExportPlan(
        manifest=manifest,
        target_root=target_root,
        source_sha256=source_sha256,
        writes=write_operations,
        deletes=delete_operations,
    )

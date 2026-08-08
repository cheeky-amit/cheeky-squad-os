"""Receipts for files owned by a portable squad export."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import PurePosixPath

from cheeky_squad_portability.contracts import Destination
from cheeky_squad_portability.json_io import JsonValue, pretty_json


class ReceiptError(ValueError):
    """A receipt is malformed or cannot authorize the requested operation."""


def normalize_relative_path(value: str, *, label: str = "path") -> str:
    """Return one unambiguous POSIX file path contained by an export root."""

    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise ReceiptError(f"{label} must be a non-empty POSIX relative path")
    path = PurePosixPath(value)
    normalized = path.as_posix()
    if (
        value.startswith("/")
        or path.is_absolute()
        or ".." in path.parts
        or normalized in {"", "."}
        or normalized != value
    ):
        raise ReceiptError(f"{label} must be a normalized relative path without traversal")
    return normalized


def _text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReceiptError(f"{label} must be a non-empty string")
    return value


def _digest(value: object, label: str) -> str:
    digest = _text(value, label)
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ReceiptError(f"{label} must be a lowercase SHA-256 digest")
    return digest


def _mapping(value: object, label: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or any(not isinstance(key, str) for key in value):
        raise ReceiptError(f"{label} must be an object with string keys")
    return value


def _sequence(value: object, label: str) -> Sequence[object]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        raise ReceiptError(f"{label} must be an array")
    return value


def _reject_unknown(data: Mapping[str, object], allowed: set[str], label: str) -> None:
    unknown = sorted(set(data) - allowed)
    if unknown:
        raise ReceiptError(f"{label} has unknown fields: {', '.join(unknown)}")


@dataclass(frozen=True)
class ReceiptFile:
    """One generated file, excluding the receipt itself."""

    path: str
    sha256: str
    executable: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", normalize_relative_path(self.path, label="file.path"))
        _digest(self.sha256, "file.sha256")
        if not isinstance(self.executable, bool):
            raise ReceiptError("file.executable must be a boolean")

    @classmethod
    def from_dict(cls, value: object, label: str) -> ReceiptFile:
        data = _mapping(value, label)
        _reject_unknown(data, {"path", "sha256", "executable"}, label)
        executable = data.get("executable", False)
        if not isinstance(executable, bool):
            raise ReceiptError(f"{label}.executable must be a boolean")
        return cls(
            path=_text(data.get("path"), f"{label}.path"),
            sha256=_digest(data.get("sha256"), f"{label}.sha256"),
            executable=executable,
        )

    def to_dict(self) -> dict[str, JsonValue]:
        return {
            "path": self.path,
            "sha256": self.sha256,
            "executable": self.executable,
        }


@dataclass(frozen=True)
class ExportReceipt:
    """Authorization record used by re-export, validation, and uninstall."""

    squad_id: str
    destination: Destination
    export_version: str
    source_sha256: str
    files: tuple[ReceiptFile, ...]
    schema_version: int = field(default=1, init=False)

    def __post_init__(self) -> None:
        _text(self.squad_id, "receipt.squad_id")
        _text(self.export_version, "receipt.export_version")
        _digest(self.source_sha256, "receipt.source_sha256")
        paths = [item.path for item in self.files]
        if paths != sorted(paths):
            raise ReceiptError("receipt.files must be sorted by path")
        if len(paths) != len(set(paths)):
            raise ReceiptError("receipt.files must not contain duplicate paths")

    @classmethod
    def from_dict(cls, value: object) -> ExportReceipt:
        data = _mapping(value, "receipt")
        _reject_unknown(
            data,
            {
                "schema_version",
                "squad_id",
                "destination",
                "export_version",
                "source_sha256",
                "files",
            },
            "receipt",
        )
        if data.get("schema_version") != 1:
            raise ReceiptError("receipt.schema_version must be 1")
        try:
            destination = Destination(_text(data.get("destination"), "receipt.destination"))
        except ValueError as error:
            raise ReceiptError("receipt.destination is invalid") from error
        return cls(
            squad_id=_text(data.get("squad_id"), "receipt.squad_id"),
            destination=destination,
            export_version=_text(data.get("export_version"), "receipt.export_version"),
            source_sha256=_digest(data.get("source_sha256"), "receipt.source_sha256"),
            files=tuple(
                ReceiptFile.from_dict(item, f"receipt.files[{index}]")
                for index, item in enumerate(_sequence(data.get("files"), "receipt.files"))
            ),
        )

    @classmethod
    def from_bytes(cls, content: bytes) -> ExportReceipt:
        try:
            value = json.loads(content.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ReceiptError("receipt must be valid UTF-8 JSON") from error
        return cls.from_dict(value)

    def to_dict(self) -> dict[str, JsonValue]:
        return {
            "schema_version": self.schema_version,
            "squad_id": self.squad_id,
            "destination": self.destination.value,
            "export_version": self.export_version,
            "source_sha256": self.source_sha256,
            "files": [item.to_dict() for item in self.files],
        }

    def to_bytes(self) -> bytes:
        return pretty_json(self.to_dict()).encode("utf-8")

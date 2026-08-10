"""Stable JSON encoding used by hashes, plans, fixtures, and provider adapters."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from typing import TypeAlias

JsonScalar: TypeAlias = None | bool | int | float | str
JsonValue: TypeAlias = JsonScalar | list["JsonValue"] | dict[str, "JsonValue"]
JsonMapping: TypeAlias = Mapping[str, JsonValue]


def canonical_json_bytes(value: JsonValue) -> bytes:
    """Encode JSON deterministically for hashing; no presentation whitespace."""

    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def pretty_json(value: JsonValue) -> str:
    """Encode canonical data for checked-in artifacts and human review."""

    return json.dumps(value, ensure_ascii=False, allow_nan=False, indent=2, sort_keys=True) + "\n"


def sha256_bytes(content: bytes) -> str:
    """Return a lowercase SHA-256 digest."""

    return hashlib.sha256(content).hexdigest()


def sorted_unique(values: Sequence[str]) -> tuple[str, ...]:
    """Normalize set-like string arrays without accepting empty values."""

    return tuple(sorted(set(values)))

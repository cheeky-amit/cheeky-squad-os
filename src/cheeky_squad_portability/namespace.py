"""Stable provider-safe namespaces for portable squad artifacts."""

from __future__ import annotations

from cheeky_squad_portability.errors import ContractError

SQUAD_ID_MAX_LENGTH = 63
ROLE_ID_MAX_LENGTH = 64


def provider_namespace(squad_id: str) -> str:
    """Encode a squad ID injectively using provider-safe lowercase text.

    A literal hyphen becomes ``-h`` and a namespace dot becomes ``-d``. Because
    every input hyphen is escaped, the representation can be decoded without
    ambiguity. The manifest contract bounds input length, so output is bounded
    without lossy truncation or probabilistic hashes.
    """

    if not squad_id or len(squad_id) > SQUAD_ID_MAX_LENGTH:
        raise ContractError(f"squad.id must contain at most {SQUAD_ID_MAX_LENGTH} characters")
    encoded = squad_id.replace("-", "-h").replace(".", "-d")
    if len(encoded) > SQUAD_ID_MAX_LENGTH * 2:
        raise ContractError("provider namespace exceeds its bounded representation")
    return encoded


def provider_role_id(squad_id: str, role_id: str) -> str:
    """Return the shared provider discovery ID for a canonical role."""

    if not role_id or len(role_id) > ROLE_ID_MAX_LENGTH:
        raise ContractError(f"role.id must contain at most {ROLE_ID_MAX_LENGTH} characters")
    return f"{provider_namespace(squad_id)}--{role_id}"

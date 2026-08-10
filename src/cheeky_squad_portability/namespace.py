"""Stable provider-safe namespaces for portable squad artifacts."""

from __future__ import annotations

from hashlib import sha256

from cheeky_squad_portability.errors import ContractError

SQUAD_ID_MAX_LENGTH = 63
ROLE_ID_MAX_LENGTH = 64
PROVIDER_NAMESPACE_MAX_LENGTH = 31
PROVIDER_ROLE_ID_MAX_LENGTH = 64
PROVIDER_SKILL_ID_MAX_LENGTH = 64
_DIGEST_LENGTH = 12


def _bounded_identifier(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    digest = sha256(value.encode("utf-8")).hexdigest()[:_DIGEST_LENGTH]
    prefix = value[: limit - _DIGEST_LENGTH - 1].rstrip("-")
    return f"{prefix}-{digest}"


def provider_namespace(squad_id: str) -> str:
    """Encode a squad ID collision-resistently using provider-safe lowercase text.

    A literal hyphen becomes ``-h`` and a namespace dot becomes ``-d``. Because
    every input hyphen is escaped, short representations remain reversible. Long
    representations keep a readable prefix and a stable SHA-256 suffix.
    """

    if not squad_id or len(squad_id) > SQUAD_ID_MAX_LENGTH:
        raise ContractError(f"squad.id must contain at most {SQUAD_ID_MAX_LENGTH} characters")
    encoded = squad_id.replace("-", "-h").replace(".", "-d")
    return _bounded_identifier(encoded, PROVIDER_NAMESPACE_MAX_LENGTH)


def provider_role_id(squad_id: str, role_id: str) -> str:
    """Return the shared provider discovery ID for a canonical role."""

    if not role_id or len(role_id) > ROLE_ID_MAX_LENGTH:
        raise ContractError(f"role.id must contain at most {ROLE_ID_MAX_LENGTH} characters")
    namespace = provider_namespace(squad_id)
    component_limit = PROVIDER_ROLE_ID_MAX_LENGTH - len(namespace) - 2
    role_component = _bounded_identifier(role_id, component_limit)
    return f"{namespace}--{role_component}"


def provider_role_skill_id(squad_id: str, role_id: str) -> str:
    """Return a kind-marked Codex role-skill identifier."""

    if not role_id or len(role_id) > ROLE_ID_MAX_LENGTH:
        raise ContractError(f"role.id must contain at most {ROLE_ID_MAX_LENGTH} characters")
    namespace = provider_namespace(squad_id)
    marker = "-role-"
    component_limit = PROVIDER_SKILL_ID_MAX_LENGTH - len(namespace) - len(marker)
    encoded_component = role_id.replace("-", "-h")
    bounded_component = _bounded_identifier(encoded_component, component_limit)
    return f"{namespace}{marker}{bounded_component}"


def provider_dispatch_skill_id(squad_id: str) -> str:
    """Return a Codex dispatch-skill identifier distinct from every role skill."""

    identifier = f"{provider_namespace(squad_id)}-squad-dispatch"
    if len(identifier) > PROVIDER_SKILL_ID_MAX_LENGTH:
        raise ContractError("provider dispatch skill identifier exceeds its bound")
    return identifier

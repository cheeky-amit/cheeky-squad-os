"""Collect the static runtime that exported snapshots vendor."""

from __future__ import annotations

from pathlib import Path, PurePosixPath

from cheeky_squad_portability.errors import ContractError

_RUNTIME_DIRECTORIES = ("hooks", "skills", "templates")
_PRIVATE_PARTS = {"__pycache__", ".git", ".squad", "workspaces"}


def is_private_runtime_path(path: Path | PurePosixPath) -> bool:
    """Return whether a runtime-relative path is live or private state."""

    if any(part in _PRIVATE_PARTS for part in path.parts):
        return True
    if path.name.startswith(".env"):
        return True
    return path.name.endswith((".pyc", ".pyo"))


def collect_runtime_files(source_root: Path) -> dict[str, bytes]:
    """Return deterministic vendored bytes without live squad or secret state."""

    root = source_root.resolve(strict=True)
    if not root.is_dir():
        raise ContractError("runtime source_root must be a directory")

    candidates = [root / "LICENSE"]
    for directory_name in _RUNTIME_DIRECTORIES:
        directory = root / directory_name
        if directory.is_symlink():
            raise ContractError(f"runtime directory cannot be a symlink: {directory_name}")
        if directory.is_dir():
            candidates.extend(sorted(directory.rglob("*")))

    artifacts: dict[str, bytes] = {}
    for candidate in candidates:
        if not candidate.exists():
            if candidate == root / "LICENSE":
                raise ContractError("runtime source is missing LICENSE")
            continue
        relative = candidate.relative_to(root)
        if is_private_runtime_path(relative) or candidate.is_dir():
            continue
        if candidate.is_symlink() or not candidate.is_file():
            raise ContractError(f"runtime artifact must be a regular file: {relative.as_posix()}")
        resolved = candidate.resolve(strict=True)
        if not resolved.is_relative_to(root):
            raise ContractError(f"runtime artifact escapes source_root: {relative.as_posix()}")
        artifacts[relative.as_posix()] = candidate.read_bytes()
    return dict(sorted(artifacts.items()))

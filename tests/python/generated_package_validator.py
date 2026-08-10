"""Validate a generated standalone squad using only the Python standard library."""

from __future__ import annotations

import argparse
import json
import subprocess
import tomllib
from pathlib import Path


class GeneratedPackageError(ValueError):
    """Raised when a generated package is incomplete or malformed."""


def _read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GeneratedPackageError(f"invalid JSON artifact: {path}") from error


def _required_file(root: Path, relative: str) -> Path:
    path = root / relative
    if not path.is_file() or path.is_symlink():
        raise GeneratedPackageError(f"missing regular generated artifact: {relative}")
    return path


def validate_generated_package(root: Path) -> tuple[str, ...]:
    """Validate manifests, syntax, command runtime copies, and package boundaries."""

    resolved = root.resolve(strict=True)
    if not resolved.is_dir():
        raise GeneratedPackageError("generated package root must be a directory")

    manifest = _read_json(_required_file(resolved, "shared/manifest.json"))
    _read_json(_required_file(resolved, "shared/roster.json"))
    if not isinstance(manifest, dict) or not isinstance(manifest.get("providers"), list):
        raise GeneratedPackageError("shared manifest must declare providers")
    providers = set(manifest["providers"])
    if not providers <= {"claude", "codex"} or not providers:
        raise GeneratedPackageError("shared manifest providers are invalid")

    checked: list[str] = []
    for path in sorted(resolved.rglob("*")):
        relative = path.relative_to(resolved).as_posix()
        if path.is_symlink():
            raise GeneratedPackageError(f"generated package contains a symlink: {relative}")
        if not path.is_file():
            continue
        checked.append(relative)
        if path.suffix == ".json":
            _read_json(path)
        elif path.suffix == ".toml":
            try:
                tomllib.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
                raise GeneratedPackageError(f"invalid TOML artifact: {relative}") from error
        elif path.suffix == ".sh":
            try:
                subprocess.run(
                    ["bash", "-n", str(path)],
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except (OSError, subprocess.CalledProcessError) as error:
                raise GeneratedPackageError(f"invalid Bash artifact: {relative}") from error

    source_command = _required_file(resolved, "shared/runtime/commands/squad-workflow.md")
    command_copies = [source_command]
    if "claude" in providers:
        _read_json(_required_file(resolved, ".claude-plugin/plugin.json"))
        command_copies.append(_required_file(resolved, "commands/squad-workflow.md"))
    if "codex" in providers:
        _read_json(_required_file(resolved, ".codex-plugin/plugin.json"))
        marketplace_path = _required_file(resolved, ".agents/plugins/marketplace.json")
        marketplace = _read_json(marketplace_path)
        if not isinstance(marketplace, dict):
            raise GeneratedPackageError("Codex marketplace manifest must be an object")
        plugins = marketplace.get("plugins")
        if not isinstance(plugins, list) or len(plugins) != 1:
            raise GeneratedPackageError("Codex marketplace must declare one local plugin")
        plugin = plugins[0]
        source = plugin.get("source") if isinstance(plugin, dict) else None
        plugin_path = source.get("path") if isinstance(source, dict) else None
        if not isinstance(plugin_path, str) or not plugin_path.startswith("./plugins/"):
            raise GeneratedPackageError("Codex marketplace plugin path is invalid")
        nested_root = plugin_path.removeprefix("./")
        _read_json(_required_file(resolved, f"{nested_root}/.codex-plugin/plugin.json"))
        command_copies.extend(
            [
                _required_file(resolved, "runtime/commands/squad-workflow.md"),
                _required_file(
                    resolved,
                    f"{nested_root}/runtime/commands/squad-workflow.md",
                ),
            ]
        )

    expected_command = source_command.read_bytes()
    if any(path.read_bytes() != expected_command for path in command_copies):
        raise GeneratedPackageError("vendored command runtime copies do not match")
    return tuple(checked)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="generated standalone plugin directory")
    args = parser.parse_args()
    checked = validate_generated_package(args.root)
    print(f"validated {len(checked)} generated package files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

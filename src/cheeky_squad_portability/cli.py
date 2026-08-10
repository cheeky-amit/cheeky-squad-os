"""Command-line preview, apply, validate, and uninstall for portable exports."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path

from cheeky_squad_portability.contracts import Destination, Roster, SquadManifest
from cheeky_squad_portability.exporter import (
    ExportError,
    ProviderCompilers,
    apply_export,
    apply_uninstall_export,
    plan_export,
    plan_uninstall_export,
    validate_installed_export,
)
from cheeky_squad_portability.json_io import pretty_json
from cheeky_squad_portability.migration import load_roster
from cheeky_squad_portability.runtime import collect_runtime_files


def _default_compilers() -> ProviderCompilers:
    """Load provider adapters lazily so contract-only use remains importable."""

    try:
        from cheeky_squad_portability.adapters.claude import (
            compile_claude_agents,
            compile_claude_plugin,
        )
        from cheeky_squad_portability.adapters.codex import (
            compile_codex_agents,
            compile_codex_plugin,
            compile_codex_skills,
        )
    except ImportError as error:
        raise ExportError("provider adapters are not installed") from error
    return ProviderCompilers(
        claude_agents=compile_claude_agents,
        claude_plugin=compile_claude_plugin,
        codex_agents=compile_codex_agents,
        codex_skills=compile_codex_skills,
        codex_plugin=compile_codex_plugin,
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="squad-export")
    subparsers = parser.add_subparsers(dest="verb", required=True)

    def add_export_inputs(command: argparse.ArgumentParser) -> None:
        command.add_argument("--manifest", type=Path, required=True)
        command.add_argument("--roster", type=Path, required=True)
        command.add_argument("--target", type=Path)
        command.add_argument("--home", type=Path)
        command.add_argument("--runtime-root", type=Path)
        command.add_argument("--source-root", type=Path)

    plan = subparsers.add_parser("plan")
    add_export_inputs(plan)
    plan.add_argument("--plan-file", type=Path)

    apply = subparsers.add_parser("apply")
    add_export_inputs(apply)
    apply.add_argument("--plan-file", type=Path, required=True)
    apply.add_argument("--confirm-plan-id", required=True)
    apply.add_argument("--confirm-global-write", action="store_true")

    validate = subparsers.add_parser("validate")
    validate.add_argument("--target", type=Path, required=True)
    validate.add_argument("--home", type=Path)
    validate.add_argument(
        "--destination", choices=[item.value for item in Destination], required=True
    )
    validate.add_argument("--squad-id", required=True)

    uninstall = subparsers.add_parser("uninstall")
    uninstall.add_argument("--target", type=Path, required=True)
    uninstall.add_argument("--home", type=Path)
    uninstall.add_argument(
        "--destination", choices=[item.value for item in Destination], required=True
    )
    uninstall.add_argument("--squad-id", required=True)
    uninstall.add_argument("--plan-file", type=Path)
    uninstall.add_argument("--confirm-plan-id")
    uninstall.add_argument("--confirm-global-write", action="store_true")
    return parser


def _load_inputs(manifest_path: Path, roster_path: Path) -> tuple[SquadManifest, Roster]:
    manifest = SquadManifest.from_dict(json.loads(manifest_path.read_text(encoding="utf-8")))
    roster = load_roster(json.loads(roster_path.read_text(encoding="utf-8")))
    return manifest, roster


def _runtime_bundle(runtime_root: Path | None) -> tuple[dict[str, bytes], set[str]]:
    root = (
        Path(__file__).resolve().parents[2]
        if runtime_root is None
        else runtime_root.resolve(strict=False)
    )
    if not root.is_dir() or not (root / "LICENSE").is_file():
        raise ExportError("plugin export requires --runtime-root pointing to a squad source tree")
    files = collect_runtime_files(root)
    executables = {path for path in files if path.endswith(".sh")}
    return files, executables


def _source_root(explicit: Path | None, roster_path: Path) -> Path | None:
    if explicit is not None:
        return explicit.resolve(strict=False)
    resolved = roster_path.resolve(strict=False)
    if resolved.parent.name == ".squad":
        return resolved.parent.parent
    return None


def run_cli(argv: Sequence[str], *, compilers: ProviderCompilers | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.verb in {"plan", "apply"}:
            manifest, roster = _load_inputs(args.manifest, args.roster)
            if manifest.destination is Destination.SESSION:
                selected_compilers = ProviderCompilers() if compilers is None else compilers
            else:
                selected_compilers = _default_compilers() if compilers is None else compilers
            if manifest.destination is Destination.PLUGIN:
                runtime_files, executable_paths = _runtime_bundle(args.runtime_root)
            else:
                runtime_files, executable_paths = {}, set()
            prepared = plan_export(
                manifest=manifest,
                roster=roster,
                compilers=selected_compilers,
                target_root=args.target,
                home=args.home,
                source_root=_source_root(args.source_root, args.roster),
                vendored_files=runtime_files,
                executable_paths=executable_paths,
            )
            plan_dict = prepared.plan.to_dict()
            if args.verb == "plan":
                if args.plan_file is not None:
                    args.plan_file.write_text(pretty_json(plan_dict), encoding="utf-8")
                sys.stdout.write(pretty_json(plan_dict))
                return 0
            saved_plan = json.loads(args.plan_file.read_text(encoding="utf-8"))
            if saved_plan != plan_dict:
                raise ExportError("saved preview does not byte-for-byte match the current plan")
            result = apply_export(
                prepared,
                confirmed_plan_id=args.confirm_plan_id,
                global_write_confirmed=args.confirm_global_write,
            )
            if result.session_prompt is not None:
                sys.stdout.write(f"{result.session_prompt}\n")
            else:
                sys.stdout.write(
                    pretty_json(
                        {
                            "plan_id": result.plan_id,
                            "written": list(result.written),
                            "deleted": list(result.deleted),
                        }
                    )
                )
            return 0

        destination = Destination(args.destination)
        if args.verb == "validate":
            report = validate_installed_export(
                target_root=args.target,
                destination=destination,
                squad_id=args.squad_id,
                home=args.home,
            )
            sys.stdout.write(
                pretty_json(
                    {
                        "squad_id": report.squad_id,
                        "destination": report.destination.value,
                        "checked_files": list(report.checked_files),
                    }
                )
            )
            return 0

        prepared = plan_uninstall_export(
            target_root=args.target,
            destination=destination,
            squad_id=args.squad_id,
            home=args.home,
        )
        plan_dict = prepared.plan.to_dict()
        if args.confirm_plan_id is None:
            if args.plan_file is not None:
                args.plan_file.write_text(pretty_json(plan_dict), encoding="utf-8")
            sys.stdout.write(pretty_json(plan_dict))
            return 0
        if args.plan_file is None:
            raise ExportError("uninstall apply requires --plan-file from a reviewed preview")
        saved_plan = json.loads(args.plan_file.read_text(encoding="utf-8"))
        if saved_plan != plan_dict:
            raise ExportError("saved uninstall preview does not match the current plan")
        result = apply_uninstall_export(
            prepared,
            confirmed_plan_id=args.confirm_plan_id,
            global_write_confirmed=args.confirm_global_write,
        )
        sys.stdout.write(
            pretty_json(
                {
                    "deleted": list(result.deleted),
                    "preserved_modified": list(result.preserved_modified),
                    "receipt_retained": result.receipt_retained,
                }
            )
        )
        return 0
    except (ExportError, OSError, ValueError, json.JSONDecodeError) as error:
        sys.stderr.write(f"error: {error}\n")
        return 2


def main() -> None:
    raise SystemExit(run_cli(sys.argv[1:]))


if __name__ == "__main__":
    main()

from __future__ import annotations

from pathlib import Path

import pytest

from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.runtime import collect_runtime_files

ROOT = Path(__file__).parents[2]


def test_repository_runtime_is_vendored_without_live_state() -> None:
    files = collect_runtime_files(ROOT)

    assert "LICENSE" in files
    assert "commands/squad-workflow.md" in files
    assert "hooks/session-start.sh" in files
    assert "skills/squad-roster/SKILL.md" in files
    assert "templates/partner.md" in files
    assert not any("workspaces" in path or path.startswith(".squad/") for path in files)


@pytest.mark.parametrize(
    "private_path",
    [
        "commands/.env.production",
        "hooks/credentials/token.txt",
        "skills/demo/engagement-records/customer.md",
        "templates/private-state/notes.md",
        "templates/secrets/api-key.txt",
    ],
)
def test_runtime_excludes_private_nested_state(tmp_path: Path, private_path: str) -> None:
    (tmp_path / "LICENSE").write_text("license", encoding="utf-8")
    safe = tmp_path / "commands/squad-workflow.md"
    safe.parent.mkdir(parents=True)
    safe.write_text("# Workflow\n", encoding="utf-8")
    private = tmp_path / private_path
    private.parent.mkdir(parents=True, exist_ok=True)
    private.write_text("private", encoding="utf-8")

    files = collect_runtime_files(tmp_path)

    assert files == {
        "LICENSE": b"license",
        "commands/squad-workflow.md": b"# Workflow\n",
    }


def test_runtime_rejects_symlinked_artifact(tmp_path: Path) -> None:
    (tmp_path / "LICENSE").write_text("license", encoding="utf-8")
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    target = tmp_path / "target.sh"
    target.write_text("#!/bin/sh\n", encoding="utf-8")
    (hooks / "escape.sh").symlink_to(target)

    with pytest.raises(ContractError, match="regular file"):
        collect_runtime_files(tmp_path)

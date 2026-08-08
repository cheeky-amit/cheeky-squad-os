from __future__ import annotations

from pathlib import Path

import pytest

from cheeky_squad_portability.errors import ContractError
from cheeky_squad_portability.runtime import collect_runtime_files

ROOT = Path(__file__).parents[2]


def test_repository_runtime_is_vendored_without_live_state() -> None:
    files = collect_runtime_files(ROOT)

    assert "LICENSE" in files
    assert "hooks/session-start.sh" in files
    assert "skills/squad-roster/SKILL.md" in files
    assert "templates/partner.md" in files
    assert not any("workspaces" in path or path.startswith(".squad/") for path in files)


def test_runtime_rejects_symlinked_artifact(tmp_path: Path) -> None:
    (tmp_path / "LICENSE").write_text("license", encoding="utf-8")
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    target = tmp_path / "target.sh"
    target.write_text("#!/bin/sh\n", encoding="utf-8")
    (hooks / "escape.sh").symlink_to(target)

    with pytest.raises(ContractError, match="regular file"):
        collect_runtime_files(tmp_path)

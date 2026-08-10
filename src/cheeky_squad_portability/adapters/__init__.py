"""Pure provider compilers for portable squad snapshots."""

from cheeky_squad_portability.adapters.claude import (
    claude_role_id,
    compile_claude_agents,
    compile_claude_plugin,
)
from cheeky_squad_portability.adapters.codex import (
    codex_role_id,
    compile_codex_agents,
    compile_codex_plugin,
    compile_codex_skills,
)

__all__ = [
    "claude_role_id",
    "codex_role_id",
    "compile_claude_agents",
    "compile_claude_plugin",
    "compile_codex_agents",
    "compile_codex_plugin",
    "compile_codex_skills",
]

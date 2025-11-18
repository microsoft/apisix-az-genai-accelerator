"""File I/O operations for rendering."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def ensure_parent(path: Path) -> None:
    """Ensure parent directories exist for the given path.

    Args:
        path: Path whose parent directories should be created
    """
    path.parent.mkdir(parents=True, exist_ok=True)


def atomic_write_text(path: Path, text: str, mode: int = 0o644) -> None:
    """Write text to a file atomically using a temporary file.

    Args:
        path: Destination file path
        text: Text content to write
        mode: File permissions (octal)
    """
    ensure_parent(path)

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.write(text)
            tmp.flush()
            os.fsync(tmp.fileno())
        os.replace(tmp_name, path)
        os.chmod(path, mode)
    finally:
        if os.path.exists(tmp_name):
            try:
                os.remove(tmp_name)
            except Exception:
                pass

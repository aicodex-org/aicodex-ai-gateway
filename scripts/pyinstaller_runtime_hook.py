from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path


def _bundle_root() -> Path:
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return Path(meipass)
    return Path(__file__).resolve().parent.parent


def _prepend_path(path: Path) -> None:
    if not path.exists():
        return
    current = os.environ.get("PATH", "")
    os.environ["PATH"] = str(path) if not current else f"{path}{os.pathsep}{current}"


def _install_prisma_wrapper(runtime_root: Path) -> Path:
    bin_dir = runtime_root / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    if os.name == "nt":
        wrapper_path = bin_dir / "prisma.cmd"
        wrapper_path.write_text(
            f'@echo off\r\n"{sys.executable}" --__run-prisma__ %*\r\n',
            encoding="utf-8",
        )
    else:
        wrapper_path = bin_dir / "prisma"
        wrapper_path.write_text(
            f'#!/bin/sh\nexec "{sys.executable}" --__run-prisma__ "$@"\n',
            encoding="utf-8",
        )
        wrapper_path.chmod(0o755)

    return wrapper_path


bundle_root = _bundle_root()
runtime_root = Path(tempfile.gettempdir()) / "aicodex-ai-gateway-runtime"
ui_root = runtime_root / "ui"
migration_root = runtime_root / "migrations"
bundled_prisma_cache_root = bundle_root / "prisma-cache"
prisma_cache_root = (
    bundled_prisma_cache_root if bundled_prisma_cache_root.exists() else runtime_root / "prisma-cache"
)
npm_cache_root = runtime_root / "npm-cache"

for path in (runtime_root, ui_root, migration_root, prisma_cache_root, npm_cache_root):
    path.mkdir(parents=True, exist_ok=True)

_prepend_path(bundle_root / "bin")
_prepend_path(bundle_root / "_internal" / "bin")

prisma_cli = _install_prisma_wrapper(runtime_root)
os.environ.setdefault("PRISMA_CLI_PATH", str(prisma_cli))
_prepend_path(prisma_cli.parent)

os.environ.setdefault("PRISMA_OFFLINE_MODE", "true")
os.environ.setdefault("NPM_CONFIG_CACHE", str(npm_cache_root))
os.environ.setdefault("PRISMA_BINARY_CACHE_DIR", str(prisma_cache_root))
os.environ.setdefault("LITELLM_MIGRATION_DIR", str(migration_root))
os.environ.setdefault("LITELLM_UI_PATH", str(ui_root))

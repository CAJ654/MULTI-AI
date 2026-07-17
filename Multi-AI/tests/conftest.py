"""Lets pytest collect the `.pyx` test files in this directory.

Model/test sources here are plain-Python `.pyx` files (see the module
docstrings for why) — but pytest's built-in collector hard-codes a `.py`
suffix check before it even looks at the `python_files` ini setting, and its
default import machinery derives the dotted module name from the file
suffix too. Without this hook `pytest -q` silently collects nothing; with
the hook alone (no custom import) it still fails with "No module named
test_foo". So this loads `.pyx` test files the same way every other file in
this repo loads `.pyx` model files — directly by path via
`importlib.machinery.SourceFileLoader` — instead of pytest's suffix-aware
import_path().
"""
from __future__ import annotations

import fnmatch
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest


class _PyxModule(pytest.Module):
    def _getobj(self):
        path = self.path
        name = f"multi_ai.tests.{path.stem}"
        loader = importlib.machinery.SourceFileLoader(name, str(path))
        spec = importlib.util.spec_from_file_location(name, path, loader=loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module


def pytest_collect_file(file_path: Path, parent: pytest.Collector):
    if file_path.suffix != ".pyx":
        return None
    patterns = parent.config.getini("python_files")
    if not any(fnmatch.fnmatch(file_path.name, pat) for pat in patterns):
        return None
    return _PyxModule.from_parent(parent, path=file_path)

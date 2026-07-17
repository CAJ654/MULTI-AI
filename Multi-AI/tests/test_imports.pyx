"""Validates every model file under multi_ai/models.

Model files are plain-Python ``.pyx`` sources that Python's import system
won't pick up until they're actually Cython-compiled, so this loads them
directly by file path — the same way ``multi_ai.server`` does — and checks
each declares the expected interface.

Run directly: python Multi-AI/tests/test_imports.pyx
"""
import importlib.machinery
import importlib.util
from pathlib import Path

_MODELS_DIR = Path(__file__).resolve().parent.parent / "multi_ai" / "models"
# TensorFlow/pytorch are framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}


def _load_by_path(path):
    name = f"multi_ai.models.{path.stem}"
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def test_models_loadable():
    paths = [p for p in sorted(_MODELS_DIR.glob("*.pyx")) if p.stem not in _EXCLUDED_STEMS]
    assert paths, f"no model files found in {_MODELS_DIR}"
    for path in paths:
        module = _load_by_path(path)
        assert hasattr(module, "get_info"), f"{path.stem} lacks get_info()"
        assert isinstance(module.get_info().get("name"), str), f"{path.stem} get_info() lacks a name"
        runnable = getattr(module, "_REPO_ID", None) or getattr(module, "_GGUF_SOURCE", None)
        assert runnable, f"{path.stem} declares neither _REPO_ID nor _GGUF_SOURCE"


if __name__ == "__main__":
    test_models_loadable()
    print("ok — all model files load and declare get_info + a model source")

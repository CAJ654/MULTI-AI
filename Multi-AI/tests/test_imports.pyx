"""Validates every model file under multi_ai/models.

Model files are Cython-compiled to native extension modules, so this imports
each one by name — the same way ``multi_ai.server`` does — and checks it
declares the expected interface. A model whose ``.pyx`` hasn't been compiled
raises ImportError here (run ``pip install -e . --no-deps`` to build them).

Run directly: python Multi-AI/tests/test_imports.pyx
"""
import importlib
from pathlib import Path

_MODELS_DIR = Path(__file__).resolve().parent.parent / "multi_ai" / "models"
# TensorFlow/pytorch are framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}


def _import_model(stem: str):
    return importlib.import_module(f"multi_ai.models.{stem}")


def test_models_loadable():
    stems = [p.stem for p in sorted(_MODELS_DIR.glob("*.pyx")) if p.stem not in _EXCLUDED_STEMS]
    assert stems, f"no model files found in {_MODELS_DIR}"
    for stem in stems:
        module = _import_model(stem)
        assert hasattr(module, "get_info"), f"{stem} lacks get_info()"
        assert isinstance(module.get_info().get("name"), str), f"{stem} get_info() lacks a name"
        runnable = getattr(module, "_REPO_ID", None) or getattr(module, "_GGUF_SOURCE", None)
        assert runnable, f"{stem} declares neither _REPO_ID nor _GGUF_SOURCE"


if __name__ == "__main__":
    test_models_loadable()
    print("ok — all model files load and declare get_info + a model source")

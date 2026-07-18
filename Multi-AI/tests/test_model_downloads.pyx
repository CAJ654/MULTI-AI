"""Lightweight existence checks for every model's download source.

Doesn't download any weights (some are double-digit GB and would make this
test suite unusable) — just confirms each `_REPO_ID` resolves on the
Hugging Face Hub and each `_GGUF_SOURCE` points at a real file in a real
repo, via metadata-only Hub API calls. This is exactly the class of bug the
2026-07-17 fix round kept hitting: a gated/renamed/typo'd repo id that only
surfaces once a user actually tries to chat.

Needs network access; skips (doesn't fail) a model when the Hub itself is
unreachable, but still fails on a genuine "repo/file doesn't exist" or
"gated without a token" response.

Run directly: python Multi-AI/tests/test_model_downloads.pyx
"""
from __future__ import annotations

import importlib
import os
from pathlib import Path

import pytest

_MODELS_DIR = Path(__file__).resolve().parent.parent / "multi_ai" / "models"
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}
_TOKEN = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")


def _import_model(path: Path):
    return importlib.import_module(f"multi_ai.models.{path.stem}")


def _model_paths() -> list[Path]:
    return [p for p in sorted(_MODELS_DIR.glob("*.pyx")) if p.stem not in _EXCLUDED_STEMS]


def _parse_gguf_source(source: str) -> tuple[str, str]:
    """`hf://owner/repo/file.gguf` -> (`owner/repo`, `file.gguf`)."""
    owner, repo, filename = source.removeprefix("hf://").split("/", 2)
    return f"{owner}/{repo}", filename


def _check_source(path: Path) -> None:
    from huggingface_hub import HfApi
    from huggingface_hub.utils import EntryNotFoundError, GatedRepoError, RepositoryNotFoundError

    module = _import_model(path)
    repo_id = getattr(module, "_REPO_ID", None)
    gguf = getattr(module, "_GGUF_SOURCE", None)
    assert repo_id or gguf, f"{path.stem} declares neither _REPO_ID nor _GGUF_SOURCE"

    # These mean the source itself is wrong — a real test failure. Anything
    # else (timeouts, DNS, 5xx) means we couldn't check, not that it's broken.
    broken_source = (RepositoryNotFoundError, GatedRepoError, EntryNotFoundError)
    api = HfApi()

    if repo_id:
        try:
            api.model_info(repo_id, token=_TOKEN)
        except broken_source as exc:
            raise AssertionError(f"{path.stem}: repo {repo_id!r} does not resolve: {exc}") from exc
        except Exception as exc:
            pytest.skip(f"{path.stem}: could not reach the Hugging Face Hub: {exc}")

    if gguf:
        repo, filename = _parse_gguf_source(gguf)
        try:
            exists = api.file_exists(repo, filename, token=_TOKEN)
        except broken_source as exc:
            raise AssertionError(f"{path.stem}: {gguf!r} does not resolve: {exc}") from exc
        except Exception as exc:
            pytest.skip(f"{path.stem}: could not reach the Hugging Face Hub: {exc}")
        assert exists, f"{path.stem}: {filename!r} not found in {repo!r} ({gguf})"


@pytest.mark.parametrize("path", _model_paths(), ids=lambda p: p.stem)
def test_model_source_resolves(path: Path):
    try:
        import huggingface_hub  # noqa: F401
    except ImportError:
        pytest.skip("huggingface_hub not installed")
    _check_source(path)


if __name__ == "__main__":
    failures = []
    for path in _model_paths():
        try:
            _check_source(path)
            print(f"ok   {path.stem}")
        except AssertionError as exc:
            failures.append(str(exc))
            print(f"FAIL {path.stem}: {exc}")
        except pytest.skip.Exception as exc:
            print(f"SKIP {path.stem}: {exc}")
    if failures:
        raise SystemExit(f"{len(failures)} model source(s) failed to resolve")
    print("ok — every model source resolves on the Hugging Face Hub")

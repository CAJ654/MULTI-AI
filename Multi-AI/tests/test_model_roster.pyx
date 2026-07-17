"""Confirms every model file under multi_ai/models surfaces correctly through
the API the Flutter app calls — GET /api/models — so a model added to (or
broken in) that directory doesn't silently fail to show up in the app's
dropdown (see `app/lib/chat_screen.dart`'s `_loadModels`).

Run directly: python Multi-AI/tests/test_model_roster.pyx
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import threading
import urllib.request
from pathlib import Path

_SERVER_PATH = Path(__file__).resolve().parent.parent / "multi_ai" / "server.pyx"
_MODELS_DIR = _SERVER_PATH.parent / "models"
# Mirrors multi_ai.server._EXCLUDED_STEMS: framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}


def _load_server():
    """Load multi_ai/server.pyx by path — same reason as _load_model_module
    in server.pyx itself: uncompiled .pyx sources aren't importable as
    `multi_ai.server` until Cython-compiled."""
    name = "multi_ai.server"
    loader = importlib.machinery.SourceFileLoader(name, str(_SERVER_PATH))
    spec = importlib.util.spec_from_file_location(name, _SERVER_PATH, loader=loader)
    if spec is None:
        raise RuntimeError(f"could not load server module: {_SERVER_PATH}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def test_roster_matches_model_files():
    server = _load_server()
    expected_ids = {p.stem for p in _MODELS_DIR.glob("*.pyx") if p.stem not in _EXCLUDED_STEMS}
    assert expected_ids, f"no model files found in {_MODELS_DIR}"

    models = server._list_models()
    listed_ids = {m["id"] for m in models}
    assert listed_ids == expected_ids

    for entry in models:
        assert entry["name"], f"{entry['id']} has an empty name"
        # Every remaining model declares a _REPO_ID or _GGUF_SOURCE (models
        # that couldn't run were deleted from the project, per the README) —
        # a False here means a model regressed to stub-only.
        assert entry["available"] is True, f"{entry['id']} isn't available: {entry['name']}"
        if "gguf" in entry:
            assert entry["gguf"].startswith("hf://"), entry["gguf"]


def test_api_models_endpoint_matches_roster():
    """Exercises the real HTTP path the Flutter app hits, not just the
    internal helper — catches wiring bugs between _list_models() and
    do_GET()."""
    server = _load_server()
    httpd = server._Server(("localhost", 0), server._Handler)
    port = httpd.server_address[1]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/api/models", timeout=10) as resp:
            payload = json.load(resp)
    finally:
        httpd.shutdown()
        thread.join(timeout=5)

    assert payload["models"] == server._list_models()


if __name__ == "__main__":
    test_roster_matches_model_files()
    test_api_models_endpoint_matches_roster()
    print("ok — model roster matches models/ and the /api/models endpoint")

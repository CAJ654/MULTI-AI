"""Confirms the hardware-fit ratings the app colours green/yellow/red are
sane — the ratings drive whether a user commits to a multi-gigabyte download
(see `app/lib/model_fit_badge.dart`), so a formula regression here quietly
tells people to fetch models their machine can't run.

Ratings are exercised against *synthetic* specs rather than whatever GPU the
test happens to run on: the interesting cases (a 4GB card, no GPU at all) are
mostly machines CI will never be, and a test that says something different on
every developer's laptop can't catch a regression.

Run directly: python Multi-AI/tests/test_hardware_fit.pyx
"""
from __future__ import annotations

import importlib
import json
import threading
import urllib.request


def _load(name: str):
    """Import a compiled multi_ai extension module (built by
    `pip install -e . --no-deps`)."""
    return importlib.import_module(f"multi_ai.{name}")


# A 12GB laptop GPU with 32GB of system RAM — the machine this roster was
# curated on, and the one the README's Wave 0 benchmarks were measured on.
_WORKSTATION = {"gpu_name": "Test GPU", "vram_gb": 11.94, "ram_gb": 31.38, "platform": "win32"}
# A small discrete GPU: enough for the 1-3B entries, not for a 7B.
_SMALL_GPU = {"gpu_name": "Test GPU", "vram_gb": 4.0, "ram_gb": 16.0, "platform": "win32"}
# No CUDA at all — the on-device GGUF path still works via CPU, the
# transformers path can't run.
_NO_GPU = {"gpu_name": None, "vram_gb": None, "ram_gb": 16.0, "platform": "linux"}


def test_unannotated_model_is_not_rated():
    """A model file with no size_gb gets no rating rather than a guess — the
    app hides the badge instead of showing a made-up verdict."""
    hardware = _load("hardware")
    assert hardware.rate_model(None, runs_on_device=False, specs=_WORKSTATION) is None
    assert hardware.rate_model(0, runs_on_device=True, specs=_WORKSTATION) is None


def test_server_model_rated_against_vram_after_4bit_quantization():
    """transformers loads _REPO_ID models in 4-bit, so a 14.5GB fp16 7B needs
    ~5GB and fits a 12GB card comfortably — rating it on the fp16 size would
    wrongly condemn most of the roster."""
    hardware = _load("hardware")
    fit = hardware.rate_model(14.5, runs_on_device=False, specs=_WORKSTATION)
    assert fit["rating"] == hardware.RATING_YES, fit
    assert fit["needs_gb"] < 14.5 / 2, fit

    # Same model, 4GB card: doesn't fit.
    assert hardware.rate_model(14.5, runs_on_device=False, specs=_SMALL_GPU)["rating"] == \
        hardware.RATING_NO


def test_server_model_without_a_gpu_is_unknown_not_a_verdict():
    """No CUDA device means no VRAM budget to compare against. That's a
    missing measurement, not a "no" — claiming either way would be a guess."""
    hardware = _load("hardware")
    fit = hardware.rate_model(14.5, runs_on_device=False, specs=_NO_GPU)
    assert fit["rating"] == hardware.RATING_UNKNOWN, fit


def test_on_device_model_that_full_offloads_is_optimal():
    """README Wave 0: falcon2_11b_on_device (6.85GB) full-offloaded at 999
    layers and ran at a usable 4.3 tok/s on this machine."""
    hardware = _load("hardware")
    fit = hardware.rate_model(6.85, runs_on_device=True, specs=_WORKSTATION)
    assert fit["rating"] == hardware.RATING_YES, fit


def test_oversized_on_device_model_is_not_recommended_despite_running():
    """README Wave 0: gptOSS (12.11GB) technically passes on this machine —
    the GPU-layer ladder rescues it onto the CPU — but at 0.1 tok/s and 198s
    per reply. "Runs" must not be shown to the user as green."""
    hardware = _load("hardware")
    fit = hardware.rate_model(12.11, runs_on_device=True, specs=_WORKSTATION)
    assert fit["rating"] == hardware.RATING_NO, fit


def test_on_device_model_beyond_ram_is_not_recommended():
    hardware = _load("hardware")
    fit = hardware.rate_model(100.0, runs_on_device=True, specs=_SMALL_GPU)
    assert fit["rating"] == hardware.RATING_NO, fit


def test_ratings_are_monotonic_in_model_size():
    """A bigger model must never rate better than a smaller one on the same
    machine — the property that makes the colours meaningful at a glance."""
    hardware = _load("hardware")
    order = {
        hardware.RATING_YES: 3,
        hardware.RATING_MAYBE: 2,
        hardware.RATING_NO: 1,
    }
    for on_device in (False, True):
        ranks = [
            order[hardware.rate_model(size, runs_on_device=on_device, specs=_WORKSTATION)["rating"]]
            for size in (0.5, 1.5, 3.0, 6.0, 9.0, 14.0, 25.0, 60.0)
        ]
        assert ranks == sorted(ranks, reverse=True), (on_device, ranks)


def test_every_listed_model_carries_a_fit():
    """The app shows a badge per model card, so a model that reaches the
    roster without a rating leaves a visible hole."""
    server = _load("server")
    for entry in server._list_models():
        if not entry.get("available"):
            continue
        fit = entry.get("fit")
        assert fit, f"{entry['id']} has no fit rating"
        assert fit["reason"], f"{entry['id']} has an empty fit reason"
        assert fit["rating"] in {
            "optimal", "possible", "not_recommended", "unknown",
        }, fit


def test_api_device_endpoint():
    """Exercises the real HTTP route the app calls for the Models-tab header."""
    server = _load("server")
    httpd = server._Server(("localhost", 0), server._Handler)
    port = httpd.server_address[1]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/api/device", timeout=10) as resp:
            payload = json.load(resp)
    finally:
        httpd.shutdown()
        thread.join(timeout=5)

    # Values depend on the host, but the keys the app reads must always exist.
    for key in ("gpu_name", "vram_gb", "ram_gb"):
        assert key in payload, payload


if __name__ == "__main__":
    test_unannotated_model_is_not_rated()
    test_server_model_rated_against_vram_after_4bit_quantization()
    test_server_model_without_a_gpu_is_unknown_not_a_verdict()
    test_on_device_model_that_full_offloads_is_optimal()
    test_oversized_on_device_model_is_not_recommended_despite_running()
    test_on_device_model_beyond_ram_is_not_recommended()
    test_ratings_are_monotonic_in_model_size()
    test_every_listed_model_carries_a_fit()
    test_api_device_endpoint()
    print("ok — hardware fit ratings behave")

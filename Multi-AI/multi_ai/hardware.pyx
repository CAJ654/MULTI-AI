"""Host hardware detection and per-model fit ratings.

Answers "can this machine actually run that model?" so the app can colour each
model green (optimal) / yellow (possible) / red (not recommended) instead of
letting the user discover the answer as an OOM ten minutes into a download.

Two very different budgets are at play, matching the two ways this project runs
a model (see server.pyx's module docstring):

  _REPO_ID models   the Python backend loads them through transformers, 4-bit
                    quantized on the GPU, so the binding constraint is VRAM.
  _GGUF_SOURCE      the Flutter app runs them in-process via llama.cpp, which
                    offloads to the GPU when the weights fit and otherwise
                    falls back to CPU + system RAM (correct, but much slower).

``size_gb`` in a model's ``get_info()`` means different things for those two
cases — full-precision checkpoint size for a repo, actual quantized file size
for a GGUF — so each gets its own estimator rather than one shared formula.

Detection is stdlib-only for RAM and lazily imports torch for VRAM: listing
models must keep working on a machine that never installed the heavy deps, so
anything undetectable degrades to a null budget and an "unknown" rating rather
than an error.
"""
from __future__ import annotations

import ctypes
import os
import sys

# Ratings, worst to best. The app maps these to red/yellow/green.
RATING_NO = "not_recommended"
RATING_MAYBE = "possible"
RATING_YES = "optimal"
RATING_UNKNOWN = "unknown"

# Headroom below which a model is "optimal" rather than merely "possible":
# a model filling >70% of the budget leaves nothing for a long context window,
# and on the GPU nothing for the desktop compositor either.
_COMFORT = 0.7

# transformers loads _REPO_ID models in 4-bit (see server.pyx _load_model), so
# the weights shrink ~4x off the fp16 checkpoint size that size_gb reports.
_FP16_TO_4BIT = 4.0
# 4-bit quantization isn't exactly 4x — scales/zero-points and the layers left
# in higher precision add back a few percent.
_QUANT_OVERHEAD = 1.15
# CUDA context, activations and KV cache, on top of the weights themselves.
_GPU_WORKSPACE_GB = 1.2

# A GGUF file is already quantized, so it loads roughly at its download size.
_GGUF_OVERHEAD = 1.1
# llama.cpp KV cache and compute buffers.
_GGUF_WORKSPACE_GB = 0.8

# The OS, the app and everything else the user has open need RAM too, so only
# part of total RAM is ever really available for CPU inference.
_RAM_USABLE = 0.7

# Above this, a model that spills out of VRAM onto the CPU stops being merely
# slow and becomes unusable. Calibrated on the README's Wave 0 benchmark:
# gptOSS (12.11GB) rescued onto the CPU by the GPU-layer ladder managed
# 0.1 tok/s — 40.9s to first token, 198.5s for one short reply — while
# falcon2_11b (6.85GB) full-offloaded at a usable 4.3 tok/s. "It runs" and
# "you'd wait three minutes for a sentence" deserve different colours.
_CPU_FALLBACK_LIMIT_GB = 10.0

_cached_specs: dict | None = None


def _total_ram_gb() -> float | None:
    """Total physical RAM, or None if this platform won't say."""
    if sys.platform == "win32":
        class _MemoryStatusEx(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_uint32),
                ("dwMemoryLoad", ctypes.c_uint32),
                ("ullTotalPhys", ctypes.c_uint64),
                ("ullAvailPhys", ctypes.c_uint64),
                ("ullTotalPageFile", ctypes.c_uint64),
                ("ullAvailPageFile", ctypes.c_uint64),
                ("ullTotalVirtual", ctypes.c_uint64),
                ("ullAvailVirtual", ctypes.c_uint64),
                ("ullAvailExtendedVirtual", ctypes.c_uint64),
            ]

        status = _MemoryStatusEx()
        status.dwLength = ctypes.sizeof(_MemoryStatusEx)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return None
        return status.ullTotalPhys / (1024 ** 3)

    try:
        return (os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")) / (1024 ** 3)
    except (ValueError, OSError, AttributeError):
        # macOS in particular doesn't reliably expose SC_PHYS_PAGES.
        return None


def _gpu_specs() -> tuple:
    """(gpu_name, vram_gb) for the primary GPU, (None, None) without one.

    torch is imported here rather than at module scope so /api/models keeps
    working on a machine that only ever runs on-device GGUF models.
    """
    try:
        import torch
    except Exception:
        return None, None
    try:
        if not torch.cuda.is_available():
            return None, None
        props = torch.cuda.get_device_properties(0)
        return props.name, props.total_memory / (1024 ** 3)
    except Exception:
        return None, None


def detect_specs(refresh: bool = False) -> dict:
    """Describe the machine this server is running on.

    Cached: probing CUDA costs a torch import and a context init, and none of
    these numbers change while the process is alive.
    """
    global _cached_specs
    if _cached_specs is not None and not refresh:
        return _cached_specs

    gpu_name, vram_gb = _gpu_specs()
    ram_gb = _total_ram_gb()
    _cached_specs = {
        "gpu_name": gpu_name,
        "vram_gb": round(vram_gb, 2) if vram_gb else None,
        "ram_gb": round(ram_gb, 2) if ram_gb else None,
        "platform": sys.platform,
    }
    return _cached_specs


def _rate(need_gb: float, budget_gb: float | None) -> str:
    if not budget_gb:
        return RATING_UNKNOWN
    if need_gb <= budget_gb * _COMFORT:
        return RATING_YES
    if need_gb <= budget_gb:
        return RATING_MAYBE
    return RATING_NO


def _gb(value: float) -> str:
    return f"{value:.1f} GB"


def _rate_server_model(size_gb: float, specs: dict) -> dict:
    """A transformers/_REPO_ID model: 4-bit on the GPU, so VRAM decides."""
    need = size_gb / _FP16_TO_4BIT * _QUANT_OVERHEAD + _GPU_WORKSPACE_GB
    vram = specs.get("vram_gb")
    if not vram:
        return {
            "rating": RATING_UNKNOWN,
            "needs_gb": round(need, 1),
            "reason": f"Needs about {_gb(need)} of VRAM (4-bit); no CUDA GPU detected here.",
        }
    rating = _rate(need, vram)
    if rating == RATING_YES:
        reason = f"Needs about {_gb(need)} of your {_gb(vram)} VRAM — comfortable fit."
    elif rating == RATING_MAYBE:
        reason = (
            f"Needs about {_gb(need)} of your {_gb(vram)} VRAM — it fits, but with "
            "little room for long conversations."
        )
    else:
        reason = f"Needs about {_gb(need)} of VRAM, more than this GPU's {_gb(vram)}."
    return {"rating": rating, "needs_gb": round(need, 1), "reason": reason}


def _rate_on_device_model(size_gb: float, specs: dict) -> dict:
    """A GGUF model: llama.cpp puts what it can on the GPU, the rest on the CPU.

    Three regimes, because the cliff here is offload rather than capacity —
    a GGUF that spills out of VRAM still *runs*, just far slower:

      fits in VRAM with headroom   full offload, fast          -> optimal
      fits in VRAM but tight       llama.cpp drops some layers -> possible
      doesn't fit in VRAM          CPU-bound; slow, and past
                                   _CPU_FALLBACK_LIMIT_GB      -> not recommended
    """
    need = size_gb * _GGUF_OVERHEAD + _GGUF_WORKSPACE_GB
    vram = specs.get("vram_gb")
    ram = specs.get("ram_gb")

    if vram:
        if need <= vram * _COMFORT:
            return {
                "rating": RATING_YES,
                "needs_gb": round(need, 1),
                "reason": f"About {_gb(need)} — fits in your {_gb(vram)} VRAM, so it runs fully GPU-accelerated.",
            }
        if need <= vram:
            return {
                "rating": RATING_MAYBE,
                "needs_gb": round(need, 1),
                "reason": (
                    f"About {_gb(need)} against {_gb(vram)} VRAM — llama.cpp will keep most of "
                    "it on the GPU but drop some layers to the CPU. Usable, not fast."
                ),
            }

    if not ram:
        return {
            "rating": RATING_UNKNOWN,
            "needs_gb": round(need, 1),
            "reason": f"Needs about {_gb(need)}; couldn't read this machine's memory.",
        }

    usable = ram * _RAM_USABLE
    if need > usable:
        return {
            "rating": RATING_NO,
            "needs_gb": round(need, 1),
            "reason": f"Needs about {_gb(need)}, more than the ~{_gb(usable)} free of your {_gb(ram)} RAM.",
        }
    if need >= _CPU_FALLBACK_LIMIT_GB:
        return {
            "rating": RATING_NO,
            "needs_gb": round(need, 1),
            "reason": (
                f"About {_gb(need)} — far too big for this machine's "
                f"{_gb(vram) if vram else 'available'} VRAM, so most of it runs on the CPU. "
                "It technically works, at roughly a word every few seconds."
            ),
        }
    return {
        "rating": RATING_MAYBE,
        "needs_gb": round(need, 1),
        "reason": (
            f"About {_gb(need)} — too big for VRAM, so llama.cpp runs much of it on the CPU "
            f"using your {_gb(ram)} RAM. Expect slow replies."
        ),
    }


def rate_model(size_gb: float | None, runs_on_device: bool, specs: dict | None = None) -> dict | None:
    """Rate one model against this machine. None when size_gb is unannotated.

    Returns {"rating", "needs_gb", "reason"} — the rating is one of the
    RATING_* constants above.
    """
    if not size_gb:
        return None
    specs = specs if specs is not None else detect_specs()
    if runs_on_device:
        return _rate_on_device_model(size_gb, specs)
    return _rate_server_model(size_gb, specs)

"""Ministral 3 14B: Mistral's dense 14B edge model (Dec 2025)."""
from __future__ import annotations

# unsloth mirror: the official mistralai repo ships FP8-quantized weights,
# which need Triton FP8 kernels that don't work on Windows; this bf16 copy
# quantizes cleanly with bitsandbytes instead.
_REPO_ID = "unsloth/Ministral-3-14B-Instruct-2512"


def get_info():
    return {"name": "Ministral 3 14B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

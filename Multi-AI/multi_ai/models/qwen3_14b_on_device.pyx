"""Qwen3 14B, run on-device.

On-device sibling of ``qwen3_14b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-14B-GGUF/Qwen3-14B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 14B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "14B",
        "size_gb": 8.80,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — a large step up in reasoning quality "
        "over the 8B. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, very strong reasoning",
    }


if __name__ == "__main__":
    print(get_info())

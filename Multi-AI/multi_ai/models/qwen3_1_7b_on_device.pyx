"""Qwen3 1.7B, run on-device.

On-device sibling of ``qwen3_1_7b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-1.7B-GGUF/Qwen3-1.7B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 1.7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1.7B",
        "size_gb": 1.07,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — can switch on step-by-step reasoning "
        "for hard problems or answer directly for quick ones. Q4_K_M GGUF build runs fully "
        "on-device.",
        "speed_profile": "Very fast, solid reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())

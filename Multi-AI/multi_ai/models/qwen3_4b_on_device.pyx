"""Qwen3 4B, run on-device.

On-device sibling of ``qwen3_4b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "4B",
        "size_gb": 2.52,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model — the sweet spot between the tiny "
        "Qwen3 sizes and the 8B. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, strong reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())

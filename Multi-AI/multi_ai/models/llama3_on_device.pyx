"""Llama 3 8B Instruct, run on-device.

On-device sibling of ``llama3.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/Meta-Llama-3-8B-Instruct-GGUF/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Llama 3 8B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "8B",
        "size_gb": 4.92,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Meta Llama 3 Community License",
        "strengths": "Meta's original Llama 3 — strong general chat and instruction-following, the baseline the later 3.1/3.2 releases improved on. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

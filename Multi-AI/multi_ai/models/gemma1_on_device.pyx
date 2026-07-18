"""Gemma 2B, run on-device.

On-device sibling of ``gemma1.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://second-state/gemma-2b-it-GGUF/gemma-2b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 2B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "2B",
        "size_gb": 1.5,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Google's first Gemma generation — solid for its size but superseded by Gemma 2/3 on most benchmarks. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, modest intelligence",
    }


if __name__ == "__main__":
    print(get_info())

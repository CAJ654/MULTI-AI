"""Gemma 7B, run on-device.

On-device sibling of ``gemma_1_7b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://second-state/Gemma-7b-it-GGUF/gemma-7b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 5.13,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "The larger first-generation Gemma — clearly stronger than Gemma 1 2B, but superseded by Gemma 2 9B at a similar size. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

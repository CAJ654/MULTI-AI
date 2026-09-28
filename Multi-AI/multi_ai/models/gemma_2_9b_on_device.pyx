"""Gemma 2 9B, run on-device.

On-device sibling of ``gemma_2_9b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/gemma-2-9b-it-GGUF/gemma-2-9b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 2 9B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "9B",
        "size_gb": 5.76,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 2's mid size — a big step over the 2B on reasoning and writing, and among the strongest dense models that still fit a 12GB card at 4-bit. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

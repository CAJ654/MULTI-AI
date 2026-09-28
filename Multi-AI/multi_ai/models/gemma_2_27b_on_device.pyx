"""Gemma 2 27B, run on-device.

On-device sibling of ``gemma_2_27b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/gemma-2-27b-it-GGUF/gemma-2-27b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 2 27B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "27B",
        "size_gb": 16.65,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Gemma 2's flagship — near the top of open models of its generation. Too big for a 12GB card even at 4-bit, so expect partial CPU offload. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Slow on consumer GPUs, very strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

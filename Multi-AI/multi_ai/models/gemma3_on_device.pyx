"""Gemma 3 1B, run on-device.

On-device sibling of ``gemma3.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 3 1B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1B",
        "size_gb": 0.81,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": 'Smallest Gemma 3 — tuned for on-device/edge use with a much longer context window than earlier Gemma generations. Q4_K_M GGUF build runs fully on-device.',
        "speed_profile": "Very fast, lighter intelligence",
    }


if __name__ == "__main__":
    print(get_info())

"""Gemma 3 270M, run on-device.

On-device sibling of ``gemma_3_270m.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3-270m-it-GGUF/gemma-3-270m-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 3 270M (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "270M",
        "size_gb": 0.25,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Gemma Terms of Use",
        "strengths": "Tiny Gemma 3 built as a base for task-specific fine-tunes — handy for quick classification or extraction, weak at open-ended chat. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Very fast, limited intelligence",
    }


if __name__ == "__main__":
    print(get_info())

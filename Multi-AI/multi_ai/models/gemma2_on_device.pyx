"""Gemma 2 2B, run on-device.

On-device sibling of ``gemma2.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/gemma-2-2b-it-GGUF/gemma-2-2b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 2 2B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "2B",
        "size_gb": 1.71,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": 'Improved training recipe over Gemma 1 — noticeably better reasoning and instruction-following at the same size. Q4_K_M GGUF build runs fully on-device.',
        "speed_profile": "Fast, good intelligence for 2B",
    }


if __name__ == "__main__":
    print(get_info())

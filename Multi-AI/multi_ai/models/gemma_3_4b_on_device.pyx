"""Gemma 3 4B: Google's Gemma 3 at the 4B size, run on-device.

On-device sibling of ``gemma_3_4b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-3-4b-it-GGUF/gemma-3-4b-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Gemma 3 4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "4B",
        "size_gb": 2.49,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Gemma Terms of Use",
        "strengths": "Vision-language Gemma 3 — handles image understanding alongside text, "
        "with a long 128K context window. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, strong multimodal intelligence",
    }


if __name__ == "__main__":
    print(get_info())

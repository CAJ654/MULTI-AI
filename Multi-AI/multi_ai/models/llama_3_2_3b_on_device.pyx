"""Llama 3.2 3B Instruct: Meta's Llama 3.2 at the 3B size, run on-device.

On-device sibling of ``llama_3_2_3b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Llama-3.2-3B-Instruct-GGUF/Llama-3.2-3B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Llama 3.2 3B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 2.02,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Meta Llama 3.2 Community License",
        "strengths": "Compact Llama 3.2 tuned for edge/on-device deployment — good "
        "instruction-following for its size. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, good intelligence for 3B",
    }


if __name__ == "__main__":
    print(get_info())

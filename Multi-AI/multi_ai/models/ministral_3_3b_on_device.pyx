"""Ministral 3 3B: Mistral's compact 3B edge model (Dec 2025), run on-device.

On-device sibling of ``ministral_3_3b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://mistralai/Ministral-3-3B-Instruct-2512-GGUF/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Ministral 3 3B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 2.15,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mistral's compact edge model — vision-capable and quick, the lightest "
        "of the Ministral 3 family. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast, capable multimodal reasoning for 3B",
    }


if __name__ == "__main__":
    print(get_info())

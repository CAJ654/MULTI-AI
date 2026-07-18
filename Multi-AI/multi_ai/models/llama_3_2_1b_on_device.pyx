"""Llama 3.2 1B Instruct: Meta's smallest Llama 3.2 text model, run on-device.

On-device sibling of ``llama_3_2_1b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Llama 3.2 1B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1B",
        "size_gb": 0.81,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Meta Llama 3.2 Community License",
        "strengths": "Meta's smallest Llama 3.2 — built for low-resource/edge use; lighter "
        "reasoning than the 3B sibling. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Very fast, lighter intelligence",
    }


if __name__ == "__main__":
    print(get_info())

"""Falcon3 10B, run on-device.

On-device sibling of ``falcon_3_10b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (q4_k_m), which the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon3-10B-Instruct-GGUF/Falcon3-10B-Instruct-q4_k_m.gguf"


def get_info():
    return {
        "name": "Falcon3 10B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "10B",
        "size_gb": 6.70,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Falcon 3's largest dense model — best reasoning and coding quality in the "
        "family. q4_k_m GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, strongest Falcon 3 intelligence",
    }


if __name__ == "__main__":
    print(get_info())

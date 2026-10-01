"""Falcon3 7B, run on-device.

On-device sibling of ``falcon_3_7b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (q4_k_m), which the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon3-7B-Instruct-GGUF/Falcon3-7B-Instruct-q4_k_m.gguf"


def get_info():
    return {
        "name": "Falcon3 7B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 4.69,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License 2.0",
        "strengths": "Mid-size Falcon 3 — stronger reasoning, coding, and instruction-following "
        "than the 3B. q4_k_m GGUF build runs fully on-device.",
        "speed_profile": "Fast, good general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

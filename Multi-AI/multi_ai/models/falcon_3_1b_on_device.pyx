"""Falcon3 1B, run on-device.

On-device sibling of ``falcon_3_1b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (q4_k_m), which the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon3-1B-Instruct-GGUF/Falcon3-1B-Instruct-q4_k_m.gguf"


def get_info():
    return {
        "name": "Falcon3 1B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1B",
        "size_gb": 0.67,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License 2.0",
        "strengths": "The smallest Falcon 3 size — instruction-following and basic reasoning "
        "tuned into a footprint light enough for constrained hardware. q4_k_m GGUF build runs "
        "fully on-device.",
        "speed_profile": "Very fast, modest intelligence for its tiny size",
    }


if __name__ == "__main__":
    print(get_info())

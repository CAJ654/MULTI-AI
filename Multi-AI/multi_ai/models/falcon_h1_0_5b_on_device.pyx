"""Falcon-H1 0.5B, run on-device.

On-device sibling of ``falcon_h1_0_5b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon-H1-0.5B-Instruct-GGUF/Falcon-H1-0.5B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Falcon-H1 0.5B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "0.5B",
        "size_gb": 0.31,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Hybrid Transformer+Mamba architecture at a tiny footprint — keeps the "
        "family's cheap long-context handling even at the smallest size. Q4_K_M GGUF build "
        "runs fully on-device.",
        "speed_profile": "Very fast, efficient long-context handling",
    }


if __name__ == "__main__":
    print(get_info())

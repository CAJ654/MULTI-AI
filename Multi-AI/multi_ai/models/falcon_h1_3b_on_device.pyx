"""Falcon-H1 3B, run on-device.

On-device sibling of ``falcon_h1_3b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon-H1-3B-Instruct-GGUF/Falcon-H1-3B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Falcon-H1 3B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 1.88,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License 2.0",
        "strengths": "Hybrid Transformer+Mamba architecture — combines attention quality with "
        "state-space efficiency, so it handles very long context cheaply. Q4_K_M GGUF build "
        "runs fully on-device.",
        "speed_profile": "Fast, efficient long-context handling",
    }


if __name__ == "__main__":
    print(get_info())

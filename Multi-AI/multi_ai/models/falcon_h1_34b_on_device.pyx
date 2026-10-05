"""Falcon-H1 34B, run on-device.

On-device sibling of ``falcon_h1_34b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon-H1-34B-Instruct-GGUF/Falcon-H1-34B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Falcon-H1 34B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "34B",
        "size_gb": 21.32,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "TII Falcon License (December 2024)",
        "strengths": "Falcon-H1's flagship — hybrid Transformer+Mamba quality at frontier-ish "
        "scale, with the family's cheap long-context handling. Q4_K_M GGUF build runs fully "
        "on-device, though still a heavy download.",
        "speed_profile": "Slow, very strong general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

"""Falcon2 11B, run on-device.

On-device sibling of ``falcon2_11b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/falcon-11B-GGUF/falcon-11B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Falcon2 11B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "11B",
        "size_gb": 6.85,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "TII Falcon License 2.0",
        "strengths": "TII's multilingual generalist — decent breadth across languages for a mid-size dense model. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, solid general intelligence",
    }


if __name__ == "__main__":
    print(get_info())

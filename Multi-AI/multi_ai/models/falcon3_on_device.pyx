"""Falcon3 3B: TII's efficient Falcon 3 series, sized for single-GPU/edge use, run on-device.

On-device sibling of ``falcon3.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (q4_k_m), which the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://tiiuae/Falcon3-3B-Instruct-GGUF/Falcon3-3B-Instruct-q4_k_m.gguf"


def get_info():
    return {
        "name": "Falcon3 3B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 2.01,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "TII Falcon License 2.0",
        "strengths": "Efficient small model tuned for reasoning, coding, and instruction-following "
        "at an edge-friendly size. q4_k_m GGUF build runs fully on-device.",
        "speed_profile": "Fast, good intelligence for its size",
    }


if __name__ == "__main__":
    print(get_info())

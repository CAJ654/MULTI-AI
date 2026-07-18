"""Falcon 7B Instruct, run on-device.

On-device sibling of ``falcon_7b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://maddes8cht/tiiuae-falcon-7b-instruct-gguf/tiiuae-falcon-7b-instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Falcon 7B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 4.98,
        "modality": "Text",
        "context_tokens": 2048,
        "license": "Apache 2.0",
        "strengths": "TII's original instruction-tuned Falcon — capable general chat, but its config declares no fixed context cap and it was trained at a short 2048-token sequence length, which limits long conversations. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, dated but competent",
    }


if __name__ == "__main__":
    print(get_info())

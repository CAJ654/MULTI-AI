"""Mistral Nemo 12B, run on-device.

On-device sibling of ``mistral_nemo_12b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Mistral-Nemo-Instruct-2407-GGUF/Mistral-Nemo-Instruct-2407.Q4_K_M.gguf"


def get_info():
    return {
        "name": "Mistral Nemo 12B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "12B",
        "size_gb": 7.48,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "Mistral's multilingual model co-developed with NVIDIA — strong across non-English languages with a large 128K context window. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, strong multilingual intelligence",
    }


if __name__ == "__main__":
    print(get_info())

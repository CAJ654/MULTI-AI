"""Qwen3 8B, run on-device.

On-device sibling of ``qwen3_8b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-8B-GGUF/Qwen3-8B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 8B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "8B",
        "size_gb": 5.03,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": 'Hybrid thinking/non-thinking model — can switch on step-by-step reasoning for hard problems or answer directly for quick ones. Q4_K_M GGUF build runs fully on-device.',
        "speed_profile": "Moderate speed, strong reasoning (hybrid think mode)",
    }


if __name__ == "__main__":
    print(get_info())

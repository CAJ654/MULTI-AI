"""Qwen3 0.6B, run on-device.

On-device sibling of ``qwen3_0_6b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 0.6B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "0.6B",
        "size_gb": 0.38,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Hybrid thinking/non-thinking model at a tiny footprint — can switch on "
        "step-by-step reasoning for harder prompts or answer directly for quick ones. Q4_K_M "
        "GGUF build runs fully on-device, the lightest Qwen3 entry.",
        "speed_profile": "Very fast, modest but usable reasoning for its size",
    }


if __name__ == "__main__":
    print(get_info())

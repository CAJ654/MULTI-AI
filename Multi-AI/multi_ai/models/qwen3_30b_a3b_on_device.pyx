"""Qwen3 30B-A3B, run on-device.

On-device sibling of ``qwen3_30b_a3b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app
runs locally through llamadart. MoE weights don't shrink much from
quantization alone since every expert is still stored on disk, but only
~3B params are active per token at inference time.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-30B-A3B-GGUF/Qwen3-30B-A3B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 30B-A3B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "30B (~3B active)",
        "size_gb": 19.06,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Sparse MoE sibling of Qwen3 32B — only ~3B active parameters per token, "
        "so it reasons close to the 32B dense model's quality while generating much faster. "
        "Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Fast for its reasoning quality (sparse MoE), large download",
    }


if __name__ == "__main__":
    print(get_info())

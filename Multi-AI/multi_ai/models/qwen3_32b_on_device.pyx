"""Qwen3 32B, run on-device.

On-device sibling of ``qwen3_32b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen3-32B-GGUF/Qwen3-32B-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen3 32B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "32B",
        "size_gb": 20.12,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Qwen3's flagship dense model — hybrid thinking/non-thinking, near the top "
        "of open dense models of its generation. Q4_K_M GGUF build runs fully on-device, "
        "though still a heavy download.",
        "speed_profile": "Slow, top-tier reasoning",
    }


if __name__ == "__main__":
    print(get_info())

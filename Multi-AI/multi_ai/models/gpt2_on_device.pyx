"""GPT-2, run on-device.

On-device sibling of ``gpt2.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://mradermacher/gpt2-GGUF/gpt2.Q4_K_M.gguf"


def get_info():
    return {
        "name": "GPT-2 (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "124M",
        "size_gb": 0.11,
        "modality": "Text",
        "context_tokens": 1024,
        "license": "MIT",
        "strengths": 'A raw 2019 base model with no instruction tuning — it continues text rather than following instructions. Useful mainly as a tiny, fast baseline. Q4_K_M GGUF build runs fully on-device.',
        "speed_profile": "Very fast, minimal intelligence",
    }


if __name__ == "__main__":
    print(get_info())

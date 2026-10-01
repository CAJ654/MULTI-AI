"""Qwen2.5-Coder 32B Instruct: Alibaba's code-specialized Qwen2.5, run on-device.

On-device sibling of ``qwen2_5_coder_32b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen2.5-Coder-32B-Instruct-GGUF/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 32B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "32B",
        "size_gb": 21.4,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Qwen2.5-Coder's flagship — reported to match GPT-4o on several coding "
        "benchmarks. Q4_K_M GGUF build runs fully on-device, though still a heavy download.",
        "speed_profile": "Slow, top-tier coding intelligence",
    }


if __name__ == "__main__":
    print(get_info())

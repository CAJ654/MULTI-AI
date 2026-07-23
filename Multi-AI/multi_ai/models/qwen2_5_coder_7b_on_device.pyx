"""Qwen2.5-Coder 7B Instruct: Alibaba's code-specialized Qwen2.5, run on-device.

On-device sibling of ``qwen2_5_coder_7b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 7B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "7B",
        "size_gb": 4.68,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Code-specialized Qwen2.5 at 7B — strong code generation and refactoring. "
        "Q4_K_M GGUF build runs fully on-device with no server or network after the first "
        "download.",
        "speed_profile": "Fast for a 7B, coding-focused intelligence",
    }


if __name__ == "__main__":
    print(get_info())

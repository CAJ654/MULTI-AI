"""Qwen2.5-Coder 14B Instruct: Alibaba's code-specialized Qwen2.5, run on-device.

On-device sibling of ``qwen2_5_coder_14b.pyx``: instead of the transformers repo,
this points at a llama.cpp GGUF quantization (Q4_K_M), which the Flutter app
runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen2.5-Coder-14B-Instruct-GGUF/Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 14B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "14B",
        "size_gb": 9.37,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Code-specialized Qwen2.5 at 14B — a significant step up in code "
        "generation, debugging, and refactoring quality over the 7B. Q4_K_M GGUF build runs "
        "fully on-device.",
        "speed_profile": "Moderate speed, strong coding intelligence",
    }


if __name__ == "__main__":
    print(get_info())

"""Qwen2.5-Coder 3B Instruct: Alibaba's code-specialized Qwen2.5 at 3B, on-device.

GGUF-only on-device coder — a smaller, phone-viable sibling of
``qwen2_5_coder_7b_on_device.pyx``. Note the filename in the Qwen GGUF repo is
lowercase (``qwen2.5-coder-...q4_k_m.gguf``), unlike the 7B's; copied exactly.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/qwen2.5-coder-3b-instruct-q4_k_m.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 3B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "3B",
        "size_gb": 1.93,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Compact code-specialized Qwen2.5 — good code completion and generation "
        "for its size, small enough to run comfortably on-device including phones. Q4_K_M "
        "GGUF build.",
        "speed_profile": "Fast, good coding intelligence for 3B",
    }


if __name__ == "__main__":
    print(get_info())

"""Qwen2.5-Coder 1.5B Instruct: Alibaba's code-specialized Qwen2.5 at 1.5B, on-device.

The smallest on-device coder sibling — GGUF-only, the most phone-viable of the
Qwen2.5-Coder entries.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 1.5B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "1.5B",
        "size_gb": 1.12,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Tiny code-specialized Qwen2.5 — the lightest on-device coder, quick "
        "completions and simple generation on very modest hardware. Q4_K_M GGUF build.",
        "speed_profile": "Very fast, capable coding for its tiny size",
    }


if __name__ == "__main__":
    print(get_info())

"""Qwen2.5-Coder 0.5B Instruct: Alibaba's code-specialized Qwen2.5 at its smallest size, on-device.

The lightest on-device coder sibling — GGUF-only, even more phone-viable than
the 1.5B entry.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Qwen2.5-Coder-0.5B-Instruct-GGUF/Qwen2.5-Coder-0.5B-Instruct-Q4_K_M.gguf"


def get_info():
    return {
        "name": "Qwen2.5-Coder 0.5B Instruct (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "0.5B",
        "size_gb": 0.40,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Tiniest code-specialized Qwen2.5 — the lightest on-device coder, useful "
        "for quick completions on very constrained hardware where even the 1.5B is too heavy. "
        "Q4_K_M GGUF build.",
        "speed_profile": "Extremely fast, basic coding help only",
    }


if __name__ == "__main__":
    print(get_info())

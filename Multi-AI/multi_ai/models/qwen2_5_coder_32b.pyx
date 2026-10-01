"""Qwen2.5-Coder 32B Instruct: Alibaba's code-specialized Qwen2.5 flagship size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen2.5-Coder-32B-Instruct"


def get_info():
    return {
        "name": "Qwen2.5-Coder 32B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "32B",
        "size_gb": 69.5,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Qwen2.5-Coder's flagship — reported to match GPT-4o on several coding "
        "benchmarks. Too big for a 12GB card even at 4-bit, so expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, top-tier coding intelligence",
    }


if __name__ == "__main__":
    print(get_info())

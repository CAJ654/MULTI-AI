"""Qwen3 32B: Alibaba's Qwen3 flagship dense size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-32B"


def get_info():
    return {
        "name": "Qwen3 32B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "32B",
        "size_gb": 65.52,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Qwen3's flagship dense model — hybrid thinking/non-thinking, near the top "
        "of open dense models of its generation. Too big for a 12GB card even at 4-bit, so "
        "expect partial CPU offload.",
        "speed_profile": "Slow on consumer GPUs, top-tier reasoning",
    }


if __name__ == "__main__":
    print(get_info())

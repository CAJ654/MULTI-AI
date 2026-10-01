"""Qwen3 30B-A3B: Alibaba's Qwen3 Mixture-of-Experts release, ~3B active params per token."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen3-30B-A3B"


def get_info():
    return {
        "name": "Qwen3 30B-A3B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "30B (~3B active)",
        "size_gb": 61.98,
        "modality": "Text",
        "context_tokens": 40960,
        "license": "Apache 2.0",
        "strengths": "Sparse MoE sibling of Qwen3 32B — only ~3B active parameters per token, "
        "so it reasons close to the 32B dense model's quality while generating much faster.",
        "speed_profile": "Fast for its reasoning quality (sparse MoE), large download",
    }


if __name__ == "__main__":
    print(get_info())

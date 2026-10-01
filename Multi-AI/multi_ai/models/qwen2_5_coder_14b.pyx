"""Qwen2.5-Coder 14B Instruct: Alibaba's code-specialized Qwen2.5 at the 14B size."""
from __future__ import annotations

_REPO_ID = "Qwen/Qwen2.5-Coder-14B-Instruct"


def get_info():
    return {
        "name": "Qwen2.5-Coder 14B Instruct",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "14B",
        "size_gb": 30.4,
        "modality": "Text",
        "context_tokens": 32768,
        "license": "Apache 2.0",
        "strengths": "Code-specialized Qwen2.5 at 14B — a significant step up in code generation, "
        "debugging, and refactoring quality over the 7B, competitive with much larger "
        "general-purpose coders.",
        "speed_profile": "Moderate speed, strong coding intelligence",
    }


if __name__ == "__main__":
    print(get_info())

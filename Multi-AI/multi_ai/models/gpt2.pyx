"""GPT-2 (base, no chat tuning): OpenAI's 2019 base model — continues text, expect rambling."""
from __future__ import annotations

_REPO_ID = "gpt2"


def get_info():
    return {
        "name": "GPT-2",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "124M",
        "size_gb": 0.55,
        "modality": "Text",
        "context_tokens": 1024,
        "license": "MIT",
        "strengths": "A raw 2019 base model with no instruction tuning — it continues text rather "
        "than following instructions. Useful mainly as a tiny, fast baseline.",
        "speed_profile": "Very fast, minimal intelligence",
    }


if __name__ == "__main__":
    print(get_info())

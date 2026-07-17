"""GPT-2 (base, no chat tuning): OpenAI's 2019 base model — continues text, expect rambling."""
from __future__ import annotations

_REPO_ID = "gpt2"


def get_info():
    return {"name": "GPT-2 (base, no chat tuning)", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

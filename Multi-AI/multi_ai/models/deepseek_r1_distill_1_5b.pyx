"""DeepSeek-R1-Distill-Qwen-1.5B: DeepSeek-R1 reasoning distilled into a 1.5B Qwen backbone."""
from __future__ import annotations

_REPO_ID = "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"


def get_info():
    return {"name": "DeepSeek-R1-Distill-Qwen-1.5B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

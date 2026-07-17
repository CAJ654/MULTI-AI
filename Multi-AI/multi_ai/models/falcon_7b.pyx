"""Falcon 7B Instruct: TII's first-generation model, instruction-tuned variant."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-7b-instruct"


def get_info():
    return {"name": "Falcon 7B Instruct", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

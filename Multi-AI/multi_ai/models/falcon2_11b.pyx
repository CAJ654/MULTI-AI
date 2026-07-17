"""Falcon2 11B: TII's multilingual, multimodal-capable Falcon 2 release."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-11B"


def get_info():
    return {"name": "Falcon2 11B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

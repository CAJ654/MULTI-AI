"""FalconMamba 7B: TII's non-transformer State Space Language Model."""
from __future__ import annotations

_REPO_ID = "tiiuae/falcon-mamba-7b"


def get_info():
    return {"name": "FalconMamba 7B", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

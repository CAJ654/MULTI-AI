"""Mistral 7B Instruct: Mistral AI's original efficient 7B foundation model."""
from __future__ import annotations

_REPO_ID = "mistralai/Mistral-7B-Instruct-v0.3"


def get_info():
    return {"name": "Mistral 7B Instruct", "version": "0.1.0", "repo_id": _REPO_ID}


if __name__ == "__main__":
    print(get_info())

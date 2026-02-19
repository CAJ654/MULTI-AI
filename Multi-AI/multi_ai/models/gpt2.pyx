"""GPT-OSS stub inside package."""

from __future__ import annotations

from transformers import GPT2Model

__version__ = "0.1.0"

def get_info():
    return {"name": "GPT-OSS", "version": __version__}

if __name__ == "__main__":
    print(get_info())

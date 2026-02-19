"""GPT-OSS 20B stub inside package."""

from __future__ import annotations

from transformers import GPTNeoXForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "GPT-OSS-20B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
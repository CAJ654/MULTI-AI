"""Ministral 3 14B (v25.12): A powerful 14-billion parameter dense model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Ministral-3-14B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
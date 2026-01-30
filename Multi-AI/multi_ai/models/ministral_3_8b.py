"""Ministral 3 8B (v25.12): A powerful 8-billion parameter dense model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Ministral-3-8B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
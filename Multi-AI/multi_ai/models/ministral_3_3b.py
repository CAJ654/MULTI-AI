"""Ministral 3 3B (v25.12): A compact 3-billion parameter, highly efficient model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Ministral-3-3B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
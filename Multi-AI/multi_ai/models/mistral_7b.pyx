"""Mistral 7B (v0.1, v0.2, v0.3): The first, highly efficient, 7-billion parameter foundational model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Mistral-7B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
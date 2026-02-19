"""Llama 3 stub inside package."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Llama-3", "version": __version__}

if __name__ == "__main__":
    print(get_info())
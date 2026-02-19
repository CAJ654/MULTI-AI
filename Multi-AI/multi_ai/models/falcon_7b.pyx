"""Falcon 7B (Original): The base model for the first-generation series."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-7B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
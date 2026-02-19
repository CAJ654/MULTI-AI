"""Mixtral 8x7B: The original sparse Mixture-of-Experts model that popularized the architecture, released in 2023."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Mixtral-8x7B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
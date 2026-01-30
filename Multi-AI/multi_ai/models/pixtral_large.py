"""Pixtral Large (24.11): A 124-billion parameter multimodal model (vision + text)."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Pixtral-Large", "version": __version__}

if __name__ == "__main__":
    print(get_info())
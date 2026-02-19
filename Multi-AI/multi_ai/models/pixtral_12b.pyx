"""Pixtral 12B (24.09): A 12-billion parameter multimodal model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Pixtral-12B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
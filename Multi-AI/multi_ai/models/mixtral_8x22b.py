"""Mixtral 8x22B: A 141-billion parameter Mixture-of-Experts (MoE) model."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Mixtral-8x22B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
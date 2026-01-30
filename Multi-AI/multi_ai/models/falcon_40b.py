"""Falcon 40B (Initial Flagship Models): The original flagship model that established TII's reputation in open-source AI, freely available for both research and commercial use."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-40B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
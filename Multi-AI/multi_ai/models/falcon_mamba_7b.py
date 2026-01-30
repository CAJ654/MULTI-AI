"""Falcon Mamba (Released Aug 2024): Falcon Mamba 7B: An open-source State Space Language Model (SSLM) that utilizes a non-transformer architecture to achieve low memory usage and high-speed generation for long sequences. It outperforms traditional models like Llama 3.1 8B."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-Mamba-7B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
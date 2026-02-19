"""Falcon 2 Series (Released May 2024): A multilingual, and multimodal model series. Falcon 2 11B: A model that outperforms Meta’s Llama 3 8B and performs on par with Google’s Gemma 7B. Key Features: Includes vision-to-language capabilities."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-2-11B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
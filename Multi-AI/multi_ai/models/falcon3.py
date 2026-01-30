"""Falcon 3 Series (Released Dec 2024): This is the latest, most advanced, and efficient series designed to run on limited, single-GPU, or edge infrastructure. Sizes: 1B, 3B, 7B, and 10B parameters. Key Features: Trained on 14 trillion tokens, offering enhanced reasoning, coding, and instruction-following, supporting English, French, Spanish, and Portuguese. Multimodal Capabilities: Includes image, video, and audio understanding."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-3", "version": __version__}

if __name__ == "__main__":
    print(get_info())
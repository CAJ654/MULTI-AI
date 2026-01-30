"""Gemma 3n (E2B, E4B): These models are optimized for low-resource devices. They support multimodal input (text, image, audio)."""

from gemma import gm

__version__ = "0.1.0"

def get_info():
    return {"name": "Gemma-3n", "version": __version__}

if __name__ == "__main__":
    print(get_info())
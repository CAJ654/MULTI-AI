"""Gemma 3 (270M, 1B, 4B, 12B, 27B): This is the latest version. It has multilingual support (over 140 languages), larger context windows (up to 128K tokens), and multimodal (text and image) capabilities for most sizes."""

from gemma import gm

__version__ = "0.1.0"

def get_info():
    return {"name": "Gemma-3", "version": __version__}

if __name__ == "__main__":
    print(get_info())
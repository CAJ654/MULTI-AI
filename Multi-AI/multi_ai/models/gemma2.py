"""Gemma 2 (2B, 9B, 27B): This version has architectural improvements and efficiency gains."""

from gemma import gm

__version__ = "0.1.0"

def get_info():
    return {"name": "Gemma-2", "version": __version__}

if __name__ == "__main__":
    print(get_info())
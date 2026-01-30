"""Gemma 1 (2B, 7B): The initial release of the models focused on English text generation."""

from __future__ import annotations

from gemma import gm

__version__ = "0.1.0"

def get_info():
    return {"name": "Gemma", "version": __version__}

if __name__ == "__main__":
    print(get_info())
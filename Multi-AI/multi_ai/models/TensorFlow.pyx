"""TensorFlow stub inside package."""

from __future__ import annotations

import tensorflow as tf

__version__ = "0.1.0"

def get_info():
    return {"name": "TensorFlow", "version": __version__}

if __name__ == "__main__":
    print(get_info())
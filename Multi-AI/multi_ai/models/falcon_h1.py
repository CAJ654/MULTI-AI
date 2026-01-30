"""Falcon-H1 (Arabic/Multi-lingual): A specialized model focusing on high-performance reasoning and mathematics, optimized for Arab-centric tasks and integrated with NVIDIA NIM."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-H1", "version": __version__}

if __name__ == "__main__":
    print(get_info())
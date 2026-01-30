"""Falcon 180B (Initial Flagship Models): Released in Sept 2023, this was one of the largest and most powerful open-source models, ranking #1 on the Hugging Face Leaderboard at its time of release."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "Falcon-180B", "version": __version__}

if __name__ == "__main__":
    print(get_info())
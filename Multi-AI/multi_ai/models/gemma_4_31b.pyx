"""Gemma 4 31B: Google's Gemma 4 31B, served via transformers (4-bit)."""
from __future__ import annotations

_REPO_ID = "unsloth/gemma-4-31B-it"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Gemma 4 31B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "31B",
        "size_gb": 62.55,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Gemma 4's dense flagship — the most capable Gemma. Text + image, 256K context. Far beyond a 12GB card, so expect heavy CPU offload.",
        "speed_profile": "Slow on consumer GPUs, frontier-class open intelligence",
    }


if __name__ == "__main__":
    print(get_info())

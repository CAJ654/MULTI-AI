"""RecurrentGemma 2B: Google's RecurrentGemma 2B, served via transformers (4-bit)."""
from __future__ import annotations

# Official Google repo, gated: needs `huggingface-cli login` (or HF_TOKEN) and the
# license accepted on the model page. Server-only — llama.cpp doesn't implement
# the Griffin architecture, so there is no GGUF / on-device sibling.
_REPO_ID = "google/recurrentgemma-2b-it"


def get_info():
    return {
        "name": "RecurrentGemma 2B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "2B",
        "size_gb": 5.37,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Griffin architecture (linear recurrences + local attention) instead of a pure transformer — fixed-size state means memory doesn't grow with conversation length.",
        "speed_profile": "Fast, modest intelligence, constant memory",
    }


if __name__ == "__main__":
    print(get_info())

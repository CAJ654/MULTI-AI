"""RecurrentGemma 9B: Google's RecurrentGemma 9B, served via transformers (4-bit)."""
from __future__ import annotations

# Official Google repo, gated: needs `huggingface-cli login` (or HF_TOKEN) and the
# license accepted on the model page. Server-only — llama.cpp doesn't implement
# the Griffin architecture, so there is no GGUF / on-device sibling.
_REPO_ID = "google/recurrentgemma-9b-it"


def get_info():
    return {
        "name": "RecurrentGemma 9B",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "9B",
        "size_gb": 19.26,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Gemma Terms of Use",
        "strengths": "Larger Griffin-architecture Gemma — Gemma-1-7B-class quality with constant memory use and higher throughput on long generations.",
        "speed_profile": "Moderate speed, solid intelligence, constant memory",
    }


if __name__ == "__main__":
    print(get_info())

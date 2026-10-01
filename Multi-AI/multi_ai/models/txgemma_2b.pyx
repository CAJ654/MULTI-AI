"""TxGemma 2B Predict: Google's TxGemma 2B, served via transformers (4-bit).

Unlike the 9B/27B releases, the 2B is predict-only (structured task
predictions, not conversational chat) — there's no ``-chat`` variant.
"""
from __future__ import annotations

# Official Google repo, gated: needs `huggingface-cli login` (or HF_TOKEN) and the
# license accepted on the model page. No ungated mirror exists.
_REPO_ID = "google/txgemma-2b-predict"


def get_info():
    return {
        "name": "TxGemma 2B Predict",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "2B",
        "size_gb": 4.11,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 2B tuned for therapeutics — single-shot drug property, toxicity, "
        "and target predictions. Predict-only: no conversational reasoning like the 9B/27B "
        "chat variants, but much lighter.",
        "speed_profile": "Very fast, specialized drug-discovery predictions only",
    }


if __name__ == "__main__":
    print(get_info())

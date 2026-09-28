"""TxGemma 9B Chat: Google's TxGemma 9B Chat, served via transformers (4-bit)."""
from __future__ import annotations

# Official Google repo, gated: needs `huggingface-cli login` (or HF_TOKEN) and the
# license accepted on the model page. No ungated mirror exists.
_REPO_ID = "google/txgemma-9b-chat"


def get_info():
    return {
        "name": "TxGemma 9B Chat",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "9B",
        "size_gb": 18.48,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 9B tuned for therapeutics — drug properties, toxicity, molecule and target questions — with the ability to explain its reasoning in conversation.",
        "speed_profile": "Moderate speed, specialized drug-discovery knowledge",
    }


if __name__ == "__main__":
    print(get_info())

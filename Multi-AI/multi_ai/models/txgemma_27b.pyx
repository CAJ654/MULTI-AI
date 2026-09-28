"""TxGemma 27B Chat: Google's TxGemma 27B Chat, served via transformers (4-bit)."""
from __future__ import annotations

# Official Google repo, gated: needs `huggingface-cli login` (or HF_TOKEN) and the
# license accepted on the model page. No ungated mirror exists.
_REPO_ID = "google/txgemma-27b-chat"


def get_info():
    return {
        "name": "TxGemma 27B Chat",
        "version": "0.1.0",
        "repo_id": _REPO_ID,
        "params": "27B",
        "size_gb": 54.46,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 27B tuned for therapeutics, conversational variant. Needs CPU offload on a 12GB card.",
        "speed_profile": "Slow on consumer GPUs, specialized drug-discovery knowledge",
    }


if __name__ == "__main__":
    print(get_info())

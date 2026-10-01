"""TxGemma 2B Predict, run on-device.

On-device sibling of ``txgemma_2b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/google_txgemma-2b-predict-GGUF/google_txgemma-2b-predict-Q4_K_M.gguf"


def get_info():
    return {
        "name": "TxGemma 2B Predict (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "2B",
        "size_gb": 1.28,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 2B tuned for therapeutics — single-shot drug property, toxicity, "
        "and target predictions. Predict-only, much lighter than the chat variants. Q4_K_M "
        "GGUF build runs fully on-device.",
        "speed_profile": "Very fast, specialized drug-discovery predictions only",
    }


if __name__ == "__main__":
    print(get_info())

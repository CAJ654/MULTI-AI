"""TxGemma 9B Chat, run on-device.

On-device sibling of ``txgemma_9b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/google_txgemma-9b-chat-GGUF/google_txgemma-9b-chat-Q4_K_M.gguf"


def get_info():
    return {
        "name": "TxGemma 9B Chat (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "9B",
        "size_gb": 5.76,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 9B tuned for therapeutics — drug properties, toxicity, molecule and target questions — with the ability to explain its reasoning in conversation. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Moderate speed, specialized drug-discovery knowledge",
    }


if __name__ == "__main__":
    print(get_info())

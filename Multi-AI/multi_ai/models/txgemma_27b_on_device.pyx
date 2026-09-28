"""TxGemma 27B Chat, run on-device.

On-device sibling of ``txgemma_27b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://bartowski/google_txgemma-27b-chat-GGUF/google_txgemma-27b-chat-Q4_K_M.gguf"


def get_info():
    return {
        "name": "TxGemma 27B Chat (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "27B",
        "size_gb": 16.65,
        "modality": "Text",
        "context_tokens": 8192,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 2 27B tuned for therapeutics, conversational variant. Needs CPU offload on a 12GB card. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Slow on consumer GPUs, specialized drug-discovery knowledge",
    }


if __name__ == "__main__":
    print(get_info())

"""MedGemma 27B Text, run on-device.

On-device sibling of ``medgemma_27b_text.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/medgemma-27b-text-it-GGUF/medgemma-27b-text-it-Q4_K_M.gguf"


def get_info():
    return {
        "name": "MedGemma 27B Text (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "27B",
        "size_gb": 16.55,
        "modality": "Text",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Text-only MedGemma 27B, tuned for clinical text reasoning (EHRs, medical QA). Needs CPU offload on a 12GB card. Not medical advice. Q4_K_M GGUF build runs fully on-device.",
        "speed_profile": "Slow on consumer GPUs, strong specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())

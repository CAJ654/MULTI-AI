"""MedGemma 27B, run on-device.

On-device sibling of ``medgemma_27b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/medgemma-27b-it-GGUF/medgemma-27b-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/medgemma-27b-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "MedGemma 27B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "27B",
        "size_gb": 16.55,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Multimodal MedGemma at the 27B size — strongest MedGemma for medical images and clinical reasoning. Needs CPU offload on a 12GB card. Not medical advice. Q4_K_M GGUF build runs fully on-device. Add ~0.86GB for its vision projector.",
        "speed_profile": "Slow on consumer GPUs, strong specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())

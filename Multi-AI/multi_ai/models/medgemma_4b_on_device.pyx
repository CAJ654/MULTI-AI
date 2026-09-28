"""MedGemma 4B, run on-device.

On-device sibling of ``medgemma_4b.pyx``: a llama.cpp GGUF quantization (Q4_K_M)
that the Flutter app runs locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/medgemma-4b-it-GGUF/medgemma-4b-it-Q4_K_M.gguf"

# Vision projector (libmtmd) — without it the model loads and chats but
# can't see.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/medgemma-4b-it-GGUF/mmproj-F16.gguf"

# The app's chat input enables its image (+) / mic buttons for exactly the
# modalities listed here.
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "MedGemma 4B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "4B",
        "size_gb": 2.49,
        "modality": "Text + Image",
        "context_tokens": 131072,
        "license": "Health AI Developer Foundations Terms of Use",
        "strengths": "Gemma 3 4B adapted for medicine — reads medical images (radiology, dermatology, pathology) and answers clinical text questions. A research tool, not medical advice. Q4_K_M GGUF build runs fully on-device. Add ~0.85GB for its vision projector.",
        "speed_profile": "Moderate speed, specialized medical knowledge",
    }


if __name__ == "__main__":
    print(get_info())

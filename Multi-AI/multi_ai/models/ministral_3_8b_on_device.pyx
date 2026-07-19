"""Ministral 3 8B, run on-device.

On-device sibling of ``ministral_3_8b.pyx``: instead of the transformers repo, this
points at a llama.cpp GGUF quantization (Q4_K_M) that the Flutter app runs
locally through llamadart.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/Ministral-3-8B-Instruct-2512-GGUF/Ministral-3-8B-Instruct-2512-Q4_K_M.gguf"

# Vision needs llama.cpp's multimodal projector (libmtmd), which ships as a
# second GGUF alongside the text weights. Without it the model loads and chats
# but can't see; the app downloads both and calls loadMultimodalProjector.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/Ministral-3-8B-Instruct-2512-GGUF/mmproj-F16.gguf"
_INPUT_MODALITIES = ("text", "image")


def get_info():
    return {
        "name": "Ministral 3 8B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "8B",
        "size_gb": 5.2,
        "modality": "Text + Image",
        "context_tokens": 262144,
        "license": "Apache 2.0",
        "strengths": "Mistral's mid-size edge model — a step up in reasoning depth from the 3B "
        "variant while staying vision-capable. Q4_K_M GGUF build plus its F16 projector run "
        "fully on-device, so image input works with no server and no network.",
        "speed_profile": "Moderate speed, strong multimodal reasoning",
    }


if __name__ == "__main__":
    print(get_info())

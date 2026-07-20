"""Gemma 4 E2B: Google's on-device Gemma 4 at the smallest size, run on-device.

GGUF-only, with no ``_REPO_ID`` sibling — same shape as ``gptOSS.pyx``. Added
for the capability rather than to mirror a server entry: this is the roster's
first model that does image *and* audio input on-device.

Its predecessor ``gemma3n_on_device.pyx`` cannot: Gemma 3n's MobileNet-V5 vision
and USM audio towers have no llama.cpp projector (no mmproj exists in any GGUF
repo, and Gemma 3n is absent from llama.cpp's supported multimodal list), so
that entry is text-only on-device and says so. Gemma 4 is the fix — it appears
in llama.cpp's vision *and* mixed-modality lists, and ships an "omni" GGUF where
one file set covers all three modalities.
"""
from __future__ import annotations

_GGUF_SOURCE = "hf://unsloth/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-Q4_K_M.gguf"

# One projector covers both image and audio here — Gemma 4 E2B/E4B are "omni"
# builds, unlike the vision-only projectors the Gemma 3 and Ministral entries
# use. llama.cpp confirms audio capability at runtime via mtmd_support_audio.
_GGUF_MMPROJ_SOURCE = "hf://unsloth/gemma-4-E2B-it-GGUF/mmproj-F16.gguf"
_INPUT_MODALITIES = ("text", "image", "audio")


def get_info():
    return {
        "name": "Gemma 4 E2B (On-Device)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "E2B",
        "size_gb": 3.11,
        "modality": "Text + Image + Audio",
        "context_tokens": 131072,
        "license": "Apache 2.0",
        "strengths": "The roster's only fully multimodal on-device model — image and audio "
        "input both run through llama.cpp with no server and no network after the first "
        "download. 'E2B' denotes ~2B effective inference cost via Per-Layer Embeddings, so it "
        "stays phone-viable despite more raw parameters. Add ~0.99GB for its projector.",
        "speed_profile": "Fast for a multimodal model, phone-viable",
    }


if __name__ == "__main__":
    print(get_info())

"""Pixtral 12B: Not wired up."""
from __future__ import annotations

# Not wired to a real checkpoint: Pixtral is a multimodal (image+text) model; this chat is text-only and can't drive its vision pipeline.
_UNSUPPORTED_REASON = "Pixtral is a multimodal (image+text) model; this chat is text-only and can't drive its vision pipeline"


def get_info():
    return {"name": "Pixtral 12B", "version": "0.1.0", "repo_id": None}


if __name__ == "__main__":
    print(get_info())

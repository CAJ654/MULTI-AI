"""Kimi K3: Moonshot AI's 2.8T MoE model, run via a Colibri server this app
starts and supervises itself.

Same shape as glm_5_2_colibri.pyx — see that file for why this needs a third
dispatch path instead of _REPO_ID/_GGUF_SOURCE. Unlike GLM-5.2/Inkling, Kimi
K3 needs no int4 conversion — its QAT-trained MXFP4 experts stream straight
from the official checkpoint, so _COLIBRI_REPO_ID points directly at
moonshotai/Kimi-K3. The largest of Colibri's supported families by a wide
margin: ~1.6TB of weights on disk, so this is squarely an
enthusiast/workstation entry, not something most users will run.
"""
from __future__ import annotations

_EXTERNAL_ENDPOINT = "colibri"
_EXTERNAL_ENDPOINT_PORT = 8010
_EXTERNAL_MIN_RAM_GB = 32.0
_EXTERNAL_RECOMMENDED_RAM_GB = 32.0
_COLIBRI_REPO_ID = "moonshotai/Kimi-K3"


def get_info():
    return {
        "name": "Kimi K3 (via Colibri)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "2.8T (~104B active)",
        "size_gb": 1600,
        "modality": "Text",
        "context_tokens": 1_048_576,
        "license": "Kimi K3 License (Moonshot's own custom license, not MIT/Apache)",
        "strengths": "Moonshot's flagship 2.8T Mixture-of-Experts model run through Colibri's "
        "disk-streamed expert loading. The largest model this app can reach — a ~1.6TB "
        "download and a workstation-class RAM budget.",
        "speed_profile": "Runs via Colibri on this edge server — throughput depends on local "
        "disk speed, not this app's own generation path.",
    }


if __name__ == "__main__":
    print(get_info())

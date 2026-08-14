"""GLM-5.2: Zhipu/Z.ai's 744B MoE model, run via a Colibri server this app
starts and supervises itself.

Doesn't fit either existing path: transformers/torch can't hold a 744B
checkpoint (_REPO_ID), and llama.cpp/llamadart has no engine for GLM-5.2's
architecture (_GGUF_SOURCE). Colibri (https://github.com/JustVugg/colibri)
runs it on consumer hardware by streaming individual MoE experts from disk
instead of residing the whole model in RAM. GLM-5.2's raw checkpoint needs a
one-time int4 conversion Colibri doesn't do automatically, so
_COLIBRI_REPO_ID points at a pre-converted community mirror
(jlnsrk/GLM-5.2-colibri-int4) rather than zai-org's own repo — server.pyx
downloads it via the normal cache/download routes, then spawns
`coli serve --model <path> --port 8010` itself on first chat. The `coli`
binary itself is still a one-time manual install (see README).
"""
from __future__ import annotations

_EXTERNAL_ENDPOINT = "colibri"
_EXTERNAL_ENDPOINT_PORT = 8010
_EXTERNAL_MIN_RAM_GB = 16.0
_EXTERNAL_RECOMMENDED_RAM_GB = 24.0
_COLIBRI_REPO_ID = "jlnsrk/GLM-5.2-colibri-int4"


def get_info():
    return {
        "name": "GLM-5.2 (via Colibri)",
        "version": "0.1.0",
        "repo_id": None,
        "params": "744B (~40-55B active)",
        "size_gb": 372,
        "modality": "Text",
        "context_tokens": 1_000_000,
        "license": "Apache 2.0 (Colibri engine) / MIT (weights)",
        "strengths": "A 744B Mixture-of-Experts model run through Colibri's disk-streamed "
        "expert loading — frontier-scale reasoning on a machine with no datacenter GPU, "
        "at the cost of a ~372GB one-time download. This app downloads the weights and "
        "starts the Colibri engine for you.",
        "speed_profile": "Runs via Colibri on this edge server — throughput depends on local "
        "disk speed, not this app's own generation path.",
    }


if __name__ == "__main__":
    print(get_info())

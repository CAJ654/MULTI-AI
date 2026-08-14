"""Minimal HTTP backend for the Flutter frontend.

Stdlib-only HTTP layer; transformers/torch are imported lazily, only when a
wired model is actually used — listing models or hitting /api/hello never
needs those heavy deps installed.

Each models/<id>.pyx declares how it runs:
  _REPO_ID        — Hugging Face checkpoint the server loads via transformers
                    (4-bit quantized on GPU so 7B+ models fit in laptop VRAM)
  _GGUF_SOURCE    — llama.cpp GGUF source; the Flutter app runs these
                    on-device via llamadart, the server never loads them
  _EXTERNAL_ENDPOINT — a separate engine (currently only "colibri") this
                    server proxies chat requests to over HTTP on
                    _EXTERNAL_ENDPOINT_PORT, rather than loading the weights
                    itself via transformers. When the model also declares
                    _COLIBRI_REPO_ID, this server downloads those weights and
                    spawns/supervises the engine process too — see
                    _ensure_colibri_running.
  _GGUF_MMPROJ_SOURCE — companion multimodal-projector GGUF for a vision
                    GGUF. llama.cpp encodes images through this separate
                    file (libmtmd), so a GGUF entry without one is text-only
                    even when the underlying checkpoint has vision.
  _UNSUPPORTED_REASON — not runnable here; /api/chat explains why
  _INPUT_MODALITIES — what the checkpoint accepts beyond text ("image",
                    "audio"). Surfaced as input_modalities on /api/models,
                    which is what gates the app's attachment buttons; a
                    model that doesn't declare a modality rejects it here.

Prompts go through the tokenizer's chat template when it has one — feeding
raw text to an instruct model makes it "continue" your sentence instead of
answering it, which looks like hallucination. Template-less base models
(e.g. GPT-2) get a plain User:/Assistant: framing and honest labeling.

Weights download on first use and stay cached in ~/.cache/huggingface.
If every HTTPS request fails with CERTIFICATE_VERIFY_FAILED, see the README
note about pip-system-certs.
"""
from __future__ import annotations

import base64
import binascii
import collections
import importlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from multi_ai import hardware

_MODELS_DIR = Path(__file__).resolve().parent / "models"
# TensorFlow/pytorch are framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}

# Every model takes text; only the extras need declaring.
_DEFAULT_INPUT_MODALITIES = ("text",)

_model_module_cache: dict[str, object] = {}
_hf_model_cache: dict[str, tuple] = {}
_processor_cache: dict[str, object] = {}


def _load_model_module(model_id: str):
    """Import the compiled model extension module (models/<id>.pyd/.so).

    Model files are Cython-compiled to native extension modules, so they load
    through the normal import system. A model whose .pyx hasn't been compiled
    raises ImportError here — surfaced as an unavailable/broken entry by
    _list_models — rather than silently falling back to the .pyx source.
    """
    if model_id in _model_module_cache:
        return _model_module_cache[model_id]

    module = importlib.import_module(f"multi_ai.models.{model_id}")
    _model_module_cache[model_id] = module
    return module


def _input_modalities(module) -> tuple:
    """What this model accepts as input. Always includes "text"; a model file
    opts into more by declaring _INPUT_MODALITIES."""
    declared = getattr(module, "_INPUT_MODALITIES", None) or _DEFAULT_INPUT_MODALITIES
    return tuple(dict.fromkeys(("text",) + tuple(declared)))


def _discover_model_ids() -> list[str]:
    """The model ids present under models/.

    In development each model is a .pyx source; in a packaged build the .pyx
    (and generated .c) are stripped and only the Cython-compiled extension
    ships, so both have to be discovered or a release lists no models at all.
    The id is the module name — the filename up to its first dot, which drops
    the .pyx suffix and a compiled extension's ABI tag alike
    (foo.cp314-win_amd64.pyd, foo.cpython-314-x86_64-linux-gnu.so). A set
    dedupes the dev tree, where a model has both files side by side.
    """
    ids = set()
    for pattern in ("*.pyx", "*.pyd", "*.so"):
        for path in _MODELS_DIR.glob(pattern):
            stem = path.name.split(".", 1)[0]
            if stem and stem not in _EXCLUDED_STEMS:
                ids.add(stem)
    return sorted(ids)


def _list_models() -> list[dict]:
    # Probed once per listing, not once per model: every entry is rated against
    # the same machine, and detection lazily initializes CUDA.
    specs = hardware.detect_specs()
    entries = []
    for stem in _discover_model_ids():
        try:
            module = _load_model_module(stem)
        except Exception:
            entries.append({"id": stem, "name": f"{stem} (broken)", "available": False})
            continue
        try:
            info = module.get_info()
            name = info["name"]
        except Exception:
            info = {}
            name = stem.replace("_", " ")
        repo_id = getattr(module, "_REPO_ID", None)
        gguf = getattr(module, "_GGUF_SOURCE", None)
        mmproj = getattr(module, "_GGUF_MMPROJ_SOURCE", None)
        external_endpoint = getattr(module, "_EXTERNAL_ENDPOINT", None)
        colibri_repo_id = getattr(module, "_COLIBRI_REPO_ID", None)
        available = bool(repo_id or gguf or external_endpoint)
        entry = {
            "id": stem,
            "name": name if available else f"{name} (unavailable)",
            "available": available,
            # What the app's attachment buttons gate on. A GGUF entry only
            # earns a non-text modality by declaring _GGUF_MMPROJ_SOURCE too:
            # llama.cpp does vision through a separate projector file, so the
            # text weights alone can chat but not see.
            "input_modalities": list(_input_modalities(module)),
        }
        if gguf:
            entry["gguf"] = gguf
        if mmproj:
            entry["mmproj"] = mmproj
        if external_endpoint:
            # Distinguishes a BYO proxy target from a plain server model.
            # Chat still proxies to this port either way — see
            # _COLIBRI_REPO_ID/has_server_weights below for whether this app
            # also manages the weights it proxies to.
            entry["external_endpoint"] = external_endpoint
        # True for a _REPO_ID model (transformers-managed) or a Colibri model
        # with a _COLIBRI_REPO_ID (this app downloads the weights, then spawns
        # `coli serve` itself) — either way the cache/download/delete routes
        # work for this id. False for a plain GGUF (on-device, app-managed)
        # or a stub with neither.
        entry["has_server_weights"] = bool(repo_id or colibri_repo_id)
        # Informational only (shown in the app's Models tab) — absent for any
        # model file that hasn't been annotated yet, never required.
        if info.get("params"):
            entry["params"] = info["params"]
        if info.get("size_gb"):
            entry["size_gb"] = info["size_gb"]
        # Can this machine actually run it? A GGUF entry is rated against the
        # llama.cpp path (VRAM, else CPU + RAM), a repo against the 4-bit
        # transformers path (VRAM only), and a BYO external endpoint against
        # its own stated RAM minimums (VRAM/download-size math don't apply to
        # a disk-streaming process the user runs themselves). Absent when the
        # relevant size/RAM fields aren't annotated.
        if external_endpoint:
            fit = hardware.rate_external_model(
                getattr(module, "_EXTERNAL_MIN_RAM_GB", None),
                getattr(module, "_EXTERNAL_RECOMMENDED_RAM_GB", None),
                info.get("size_gb"),
                specs=specs,
            )
            if fit:
                entry["fit"] = fit
        elif available:
            fit = hardware.rate_model(info.get("size_gb"), runs_on_device=bool(gguf), specs=specs)
            if fit:
                entry["fit"] = fit
        if info.get("modality"):
            entry["modality"] = info["modality"]
        if info.get("context_tokens"):
            entry["context_tokens"] = info["context_tokens"]
        if info.get("license"):
            entry["license"] = info["license"]
        if info.get("strengths"):
            entry["strengths"] = info["strengths"]
        if info.get("speed_profile"):
            entry["speed_profile"] = info["speed_profile"]
        entries.append(entry)
    return entries


def _coerce_history(history) -> list[dict]:
    """Normalize the client's prior turns into role/content dicts.

    Anything malformed is dropped rather than raising: a corrupt history entry
    should cost the model some context, not fail the whole request.
    """
    if not isinstance(history, list):
        return []
    turns = []
    for item in history:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = item.get("content")
        if role in ("user", "assistant") and isinstance(content, str) and content.strip():
            turns.append({"role": role, "content": content})
    return turns


def _fit_history(tokenizer, turns: list[dict], budget: int) -> list[dict]:
    """Drop the oldest turns until the conversation fits in [budget] tokens.

    Trimming from the front keeps the newest exchange — the part the reply
    actually depends on. Without this a long chat silently overruns the
    context window and the model's answer gets cut off mid-sentence.
    """
    if budget <= 0 or not turns:
        return []

    def token_len(subset: list[dict]) -> int:
        try:
            return len(
                tokenizer.apply_chat_template(subset, add_generation_prompt=True, tokenize=True)
            )
        except Exception:
            # Template-less/base models: approximate with the plain framing.
            return len(tokenizer(_plain_transcript(subset))["input_ids"])

    kept = list(turns)
    while kept and token_len(kept) > budget:
        kept.pop(0)
        # Never open on an assistant turn — a reply with no question above it
        # reads as the model talking to itself.
        while kept and kept[0]["role"] == "assistant":
            kept.pop(0)
    return kept


def _plain_transcript(turns: list[dict]) -> str:
    """User:/Assistant: framing for base models with no chat template."""
    lines = [
        f"{'User' if t['role'] == 'user' else 'Assistant'}: {t['content']}" for t in turns
    ]
    lines.append("Assistant:")
    return "\n".join(lines)


def _build_inputs(tokenizer, prompt: str, history: list[dict] | None = None):
    turns = list(history or []) + [{"role": "user", "content": prompt}]
    if getattr(tokenizer, "chat_template", None):
        return tokenizer.apply_chat_template(
            turns,
            add_generation_prompt=True,
            return_dict=True,
            return_tensors="pt",
            enable_thinking=False,  # honored by Qwen-style templates, ignored by others
        )
    # Base models have no chat template; raw text would just get "continued".
    return tokenizer(_plain_transcript(turns), return_tensors="pt")


# ------------------------------------------------------------- attachments

_ATTACHMENT_KINDS = ("image", "audio")
# Decoded in memory before hitting disk, so a runaway upload can't fill it.
_MAX_ATTACHMENT_BYTES = 32 * 1024 * 1024


class AttachmentError(ValueError):
    """A malformed or not-permitted attachment — reported to the user as-is."""


def _attachment_suffix(attachment: dict) -> str:
    """Extension for the temp file. Processors sniff audio/image format from
    the file, but librosa/PIL pick their decoder by extension first, so a
    wrong (or missing) one turns a valid file into an unreadable one."""
    name = attachment.get("name") or ""
    suffix = Path(name).suffix
    if suffix:
        return suffix
    subtype = (attachment.get("mime_type") or "").rsplit("/", 1)[-1]
    return f".{subtype}" if subtype.isalnum() else ".bin"


def _decode_attachments(attachments: list, allowed: tuple) -> list[tuple[str, str]]:
    """Write each attachment to a temp file, returning (kind, path) pairs.

    Files rather than in-memory objects because transformers' multimodal chat
    templates accept a path for every modality — one code path for image and
    audio, and PIL/librosa do the decoding instead of us. The caller is
    responsible for deleting them (see _cleanup_attachments).
    """
    decoded: list[tuple[str, str]] = []
    try:
        for attachment in attachments:
            if not isinstance(attachment, dict):
                raise AttachmentError("each attachment must be a JSON object")
            kind = attachment.get("kind")
            if kind not in _ATTACHMENT_KINDS:
                raise AttachmentError(f"unsupported attachment kind: {kind!r}")
            if kind not in allowed:
                raise AttachmentError(
                    f"this model doesn't accept {kind} input (it accepts: {', '.join(allowed)})"
                )
            try:
                raw = base64.b64decode(attachment.get("data") or "", validate=True)
            except (binascii.Error, ValueError) as exc:
                raise AttachmentError(f"attachment data isn't valid base64: {exc}") from exc
            if not raw:
                raise AttachmentError("attachment is empty")
            if len(raw) > _MAX_ATTACHMENT_BYTES:
                raise AttachmentError(
                    f"attachment is {len(raw) // (1024 * 1024)}MB — the limit is "
                    f"{_MAX_ATTACHMENT_BYTES // (1024 * 1024)}MB"
                )
            handle, path = tempfile.mkstemp(prefix="multi_ai_", suffix=_attachment_suffix(attachment))
            with os.fdopen(handle, "wb") as fh:
                fh.write(raw)
            decoded.append((kind, path))
    except Exception:
        _cleanup_attachments(decoded)
        raise
    return decoded


def _cleanup_attachments(decoded: list[tuple[str, str]]) -> None:
    for _, path in decoded:
        try:
            os.unlink(path)
        except OSError:
            pass


def _get_or_load_processor(repo_id: str):
    """The multimodal counterpart to the tokenizer — it applies the chat
    template *and* preprocesses images/audio into the tensors the model wants."""
    if repo_id in _processor_cache:
        return _processor_cache[repo_id]
    from transformers import AutoProcessor

    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    try:
        processor = AutoProcessor.from_pretrained(repo_id, token=token, local_files_only=True)
    except OSError:
        processor = AutoProcessor.from_pretrained(repo_id, token=token)
    _processor_cache[repo_id] = processor
    return processor


def _model_context_window(model) -> int | None:
    config = model.config
    max_pos = getattr(config, "max_position_embeddings", None)
    if max_pos is None:
        max_pos = getattr(getattr(config, "text_config", None), "max_position_embeddings", None)
    return max_pos


# Both of these are VRAM ceilings, not model limits. Long-context models
# advertise windows (256K) far larger than the KV cache this card can hold, so
# neither the history nor the reply is allowed to grow to the advertised size.
# Within these bounds every model gets as much of its own window as it has —
# a 32K model is not held to what a 1K model can do, which is what a single
# flat cap used to enforce.
#
# Raising these is the knob if replies still come back cut off; the cost is
# KV-cache memory, which scales with (history + reply) x layers x heads, so a
# large model feels an increase here far more than a small one does.
_MAX_HISTORY_TOKENS = 4096
_MAX_REPLY_TOKENS = 4096


def _reply_reserve(model, requested: int | None = None) -> int:
    """How much of the window to hold back for the reply when trimming history.

    Never more than half the window. Reserving the flat _MAX_REPLY_TOKENS
    would zero out the history budget on any model whose window isn't much
    bigger than that — a 4096-window model would keep no prior turns at all
    and answer every message as if it were the first. Splitting the window
    keeps both sides usable; the reply can still overrun this at generation
    time, because by then the prompt is built and whatever the window has
    left is genuinely free.
    """
    ceiling = _MAX_REPLY_TOKENS if requested is None else requested
    window = _model_context_window(model)
    if not window:
        return ceiling
    return min(ceiling, window // 2)


def _reply_budget(max_pos: int | None, prompt_len: int, requested: int | None = None) -> int:
    """How many tokens the reply may occupy.

    Bounded by whatever is left of the model's context window after the
    prompt, so a model with absolute position embeddings (GPT-2: 1024) can
    never index off the end of its embedding table — that's a CUDA
    device-side assert which corrupts GPU state for every model until the
    server restarts, not a recoverable error.

    Returns <= 0 when the prompt has already filled the window; the caller
    reports that rather than calling generate().
    """
    ceiling = _MAX_REPLY_TOKENS if requested is None else requested
    if not max_pos:
        return ceiling
    return min(ceiling, max_pos - prompt_len)


def _history_budget(model, tokenizer, prompt: str, reply_reserve: int) -> int:
    """Tokens left for prior turns once the new message and the reply are
    accounted for. Reserving the reply up front is what stops a long history
    from crowding out the answer it was supposed to inform.

    [reply_reserve] is the *ceiling* the reply might use, not what it will:
    the real budget can't be known until the templated prompt exists, and
    that can't be built until history is trimmed. Reserving the maximum keeps
    that circularity from ever over-committing the window."""
    window = _model_context_window(model)
    if not window:
        return _MAX_HISTORY_TOKENS
    try:
        prompt_len = len(tokenizer(prompt)["input_ids"])
    except Exception:
        prompt_len = 0
    return max(0, min(_MAX_HISTORY_TOKENS, window - prompt_len - reply_reserve))


def _compute_dtype(model):
    """The float dtype the model actually computes in.

    Not `model.dtype`: under 4-bit quantization the weights are packed uint8
    and that reports the wrong thing. The embedding table is never quantized,
    so its dtype is the one the towers' outputs have to match.
    """
    import torch

    try:
        return model.get_input_embeddings().weight.dtype
    except Exception:
        return torch.bfloat16


def _build_multimodal_inputs(
    processor,
    prompt: str,
    decoded: list[tuple[str, str]],
    history: list[dict] | None = None,
):
    """Build the conversation, with the final user turn's content interleaving
    the attachments and the text, in the form multimodal templates expect.

    Prior turns carry text only — their attachments' temp files are long gone
    by now, and re-sending images the model already described would burn a lot
    of the context window for little benefit.
    """
    content = [{"type": kind, kind: path} for kind, path in decoded]
    content.append({"type": "text", "text": prompt})
    messages = [
        {"role": turn["role"], "content": [{"type": "text", "text": turn["content"]}]}
        for turn in (history or [])
    ]
    messages.append({"role": "user", "content": content})
    return processor.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
    )


def _strip_reasoning(text: str) -> str:
    """Reasoning models (DeepSeek R1, Qwen) wrap deliberation in <think> tags."""
    if "</think>" in text:
        return text.split("</think>")[-1].strip()
    stripped = text.lstrip()
    if stripped.startswith("<think>"):
        body = stripped[len("<think>"):].strip()
        return f"(model spent its token budget thinking and gave no final answer; its reasoning: {body})"
    return text


def _truncate_fake_turns(text: str) -> str:
    """Template-less base models keep going after answering, inventing further
    User:/Assistant: turns in our manual framing — keep only the first reply."""
    for marker in ("\nUser:", "User:", "\nAssistant:", "Assistant:"):
        idx = text.find(marker)
        if idx > 0:
            text = text[:idx]
    return text.strip()


def _evict_loaded_models() -> None:
    """Free VRAM before loading a different model.

    Keeping every model resident stacks them in GPU memory until CUDA OOMs —
    on a 12GB laptop GPU that happens by the second or third 7B model, so
    switching models in the app would break anything loaded afterwards.
    """
    import gc

    _hf_model_cache.clear()
    # Processors are small and CPU-side, but a stale one paired with a
    # different model's weights would preprocess to the wrong tensor shapes.
    _processor_cache.clear()
    gc.collect()
    try:
        import torch

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except ImportError:
        pass


# Optional per-model deps transformers imports lazily. Its own message already
# names the package; this maps it to the install line that fits this project.
_MISSING_DEP_HINTS = {
    "timm": "pip install timm  (Gemma 3n's vision tower is a timm model)",
    "torchvision": "pip install torchvision --index-url https://download.pytorch.org/whl/cu128",
    "librosa": "pip install librosa soundfile",
    "soundfile": "pip install librosa soundfile",
    "PIL": "pip install pillow",
    "Pillow": "pip install pillow",
}


def _load_failure_hint(exc: Exception) -> str:
    """Advice matched to why the load actually failed.

    This used to append the gated-repo/HF_TOKEN hint unconditionally, which
    sent people hunting for an auth problem when the real cause was a missing
    optional dependency (Gemma 3n needs timm) — the misleading half of the
    message was the part that looked most actionable.
    """
    text = str(exc)
    # Case-insensitively: transformers title-cases the package in its own
    # message ("requires the Torchvision library") while the import error
    # spells it as the module ("No module named 'torchvision'").
    lowered = text.lower()
    for package, install in _MISSING_DEP_HINTS.items():
        name = package.lower()
        if f"requires the {name} library" in lowered or f"no module named '{name}'" in lowered:
            return f" Install the missing dependency: {install}."
    if any(marker in text for marker in ("gated", "401", "403", "restricted", "authorized")):
        return (
            " Gated repos need a Hugging Face access token — run `huggingface-cli login` "
            "or set HF_TOKEN."
        )
    return ""


def _tokenizer_is_degenerate(tokenizer) -> bool:
    """Whether this tokenizer encodes ordinary text to nothing but <unk>.

    A half-downloaded cache is the trap: the JSON config files land before the
    vocabulary does, so `local_files_only=True` finds "a tokenizer" and loads
    it without error — but with no vocab every token maps to <unk>. The prompt
    then encodes to a single junk token, the model generates noise from it, and
    the reply comes back as "(model returned an empty response)" with nothing
    pointing at the real cause. Worse, that tokenizer gets cached in memory, so
    every later chat fails the same way until the server restarts.
    """
    unk = getattr(tokenizer, "unk_token_id", None)
    if unk is None:
        return False
    try:
        ids = tokenizer("The capital of France is Paris.", add_special_tokens=False)["input_ids"]
    except Exception:
        return False
    return not ids or all(i == unk for i in ids)


def _get_or_load_hf_model(repo_id: str) -> tuple:
    """Load (and disk-cache) the tokenizer/model for repo_id, or return the
    already-resident pair. Shared by chat generation and the standalone
    download endpoint, which just wants the weights fetched and warmed."""
    if repo_id in _hf_model_cache:
        return _hf_model_cache[repo_id]

    try:
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    except ImportError as exc:
        raise RuntimeError(
            "transformers/torch aren't installed — run: pip install torch transformers accelerate"
        ) from exc

    _evict_loaded_models()

    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    load_kwargs = {"token": token, "low_cpu_mem_usage": True, "device_map": "auto"}
    if torch.cuda.is_available():
        # 4-bit quantization so 7B+ models actually fit in laptop-GPU VRAM
        # instead of getting silently split across CPU/GPU (much slower).
        load_kwargs["quantization_config"] = BitsAndBytesConfig(
            load_in_4bit=True, bnb_4bit_compute_dtype=torch.bfloat16, bnb_4bit_quant_type="nf4"
        )
    else:
        load_kwargs["torch_dtype"] = "auto"

    def _load_with(cls, kwargs):
        # Cached models load offline — also dodges hub 429 rate limits.
        try:
            return cls.from_pretrained(repo_id, local_files_only=True, **kwargs)
        except OSError:
            return cls.from_pretrained(repo_id, **kwargs)

    def _load_model(kwargs):
        try:
            return _load_with(AutoModelForCausalLM, kwargs)
        except ValueError as exc:
            if "Unrecognized configuration class" not in str(exc):
                raise
            # Multimodal checkpoints (e.g. Ministral 3) use vision-language
            # configs that AutoModelForCausalLM refuses; they still chat
            # fine text-only through the image-text class.
            from transformers import AutoModelForImageTextToText

            return _load_with(AutoModelForImageTextToText, kwargs)

    try:
        tokenizer = _load_with(AutoTokenizer, {"token": token})
        if _tokenizer_is_degenerate(tokenizer):
            # The offline read found an incomplete cache. Re-read with the hub
            # available so the missing vocabulary files actually get fetched.
            tokenizer = AutoTokenizer.from_pretrained(repo_id, token=token)
            if _tokenizer_is_degenerate(tokenizer):
                raise RuntimeError(
                    "its tokenizer loads but encodes everything to <unk>, which means the "
                    "download is incomplete or corrupt. Delete the model from the Models tab "
                    "and download it again"
                )
        try:
            model = _load_model(load_kwargs)
        except ValueError as exc:
            if "quantized" not in str(exc) or "quantization_config" not in load_kwargs:
                raise
            # Checkpoint ships pre-quantized (e.g. Ministral 3 is FP8);
            # stacking our 4-bit config on top is rejected — load as-is.
            retry_kwargs = {k: v for k, v in load_kwargs.items() if k != "quantization_config"}
            model = _load_model(retry_kwargs)
    except Exception as exc:
        raise RuntimeError(f"could not load {repo_id}: {exc}.{_load_failure_hint(exc)}") from exc
    _hf_model_cache[repo_id] = (tokenizer, model)
    return _hf_model_cache[repo_id]


# A cap, not a target: the model still stops early at its end-of-turn token,
# so short answers stay fast. This just keeps long ones (lists, code) from
# being truncated mid-sentence.
#
# [max_new_tokens] defaults to None meaning "as much as this model's own
# window allows", up to _MAX_REPLY_TOKENS — pass an int only to cap a single
# request below that.
def _hf_generate(
    repo_id: str,
    prompt: str,
    max_new_tokens: int | None = None,
    decoded_attachments: list | None = None,
    history: list | None = None,
) -> str:
    tokenizer, model = _get_or_load_hf_model(repo_id)
    turns = _fit_history(
        tokenizer,
        _coerce_history(history),
        _history_budget(model, tokenizer, prompt, _reply_reserve(model, max_new_tokens)),
    )
    if decoded_attachments:
        # The processor owns both the chat template and the image/audio
        # preprocessing, so the text-only tokenizer path can't be reused here.
        processor = _get_or_load_processor(repo_id)
        decoder = processor if hasattr(processor, "decode") else tokenizer
        inputs = _build_multimodal_inputs(processor, prompt, decoded_attachments, turns)
        # Pixel/audio values come out of the processor as float32; the vision
        # and audio towers run in the model's compute dtype and reject a
        # mismatch. BatchFeature.to casts only floating tensors, so token ids
        # stay integral.
        inputs = inputs.to(model.device, dtype=_compute_dtype(model))
    else:
        decoder = tokenizer
        inputs = _build_inputs(tokenizer, prompt, turns).to(model.device)
    prompt_len = inputs["input_ids"].shape[1]
    token_budget = _reply_budget(_model_context_window(model), prompt_len, max_new_tokens)
    if token_budget <= 0:
        return "(your message is too long for this model's context window)"
    # `or` would be wrong here: a pad id of 0 is both valid and falsy (Gemma's
    # <pad> is 0), and silently swapping it for the eos id would make padded
    # positions read as end-of-turn once batching exists.
    pad_token_id = tokenizer.pad_token_id
    if pad_token_id is None:
        pad_token_id = tokenizer.eos_token_id
    output = model.generate(
        **inputs,
        max_new_tokens=token_budget,
        do_sample=True,
        temperature=0.7,
        pad_token_id=pad_token_id,
    )
    new_tokens = output[0][prompt_len:]
    text = decoder.decode(new_tokens, skip_special_tokens=True)
    text = _strip_reasoning(text.strip())
    ended_at_fake_turn = False
    if not getattr(tokenizer, "chat_template", None):
        truncated = _truncate_fake_turns(text)
        ended_at_fake_turn = truncated != text.strip()
        text = truncated
    if not text:
        # Distinguish "it declined to say anything" from "the prompt never
        # made it in": a prompt that encodes to a couple of tokens means the
        # tokenizer, not the model, is what went wrong.
        if prompt.strip() and prompt_len <= 4:
            return (
                "(the prompt encoded to almost nothing, so this model's tokenizer is likely "
                "incomplete — delete the model from the Models tab and download it again)"
            )
        return "(model returned an empty response)"
    # If it stopped only because it hit the cap (no natural end-of-turn token),
    # say so rather than ending mid-sentence with no explanation. Not when the
    # visible reply already ended cleanly at an invented User:/Assistant: turn.
    if len(new_tokens) >= token_budget and not ended_at_fake_turn:
        text += "\n\n… (response reached the length limit and was cut off)"
    return text


def _resolve_server_model(model_id: str):
    """Return (repo_id, kind, None) or (None, None, (message, status)) for a
    model_id that has server-managed weights: kind is "transformers" for a
    _REPO_ID model (loaded via transformers) or "colibri" for a
    _COLIBRI_REPO_ID model (fetched to disk only, then handed to a spawned
    `coli serve`) — the two need different download actions, see
    _handle_model_route."""
    try:
        module = _load_model_module(model_id)
    except Exception:
        return None, None, ("unknown model", 404)
    repo_id = getattr(module, "_REPO_ID", None)
    if repo_id:
        return repo_id, "transformers", None
    colibri_repo_id = getattr(module, "_COLIBRI_REPO_ID", None)
    if colibri_repo_id:
        return colibri_repo_id, "colibri", None
    return None, None, ("model has no server-side weights to manage", 400)


# A from_pretrained() call that fails partway (gated repo denied, network
# drop) still leaves config.json/tokenizer files in the HF cache — a few
# hundred bytes, no actual weights. Only these extensions mean the model is
# really usable; scan_cache_dir() alone can't tell a stray metadata-only
# cache from a complete download.
_WEIGHT_FILE_SUFFIXES = (".safetensors", ".bin", ".pt", ".pth", ".h5", ".msgpack", ".gguf")


def _hf_cache_repo(repo_id: str):
    from huggingface_hub import scan_cache_dir

    cache_info = scan_cache_dir()
    for repo in cache_info.repos:
        if repo.repo_id == repo_id and repo.repo_type == "model":
            return cache_info, repo
    return cache_info, None


def _repo_has_weights(repo) -> bool:
    return any(
        file.file_name.endswith(_WEIGHT_FILE_SUFFIXES)
        for revision in repo.revisions
        for file in revision.files
    )


def _model_cache_status(repo_id: str) -> dict:
    _, repo = _hf_cache_repo(repo_id)
    if repo is None or not _repo_has_weights(repo):
        return {"cached": False}
    return {"cached": True, "size_bytes": repo.size_on_disk}


def _download_hf_weights(repo_id: str) -> dict:
    _get_or_load_hf_model(repo_id)
    return _model_cache_status(repo_id)


def _download_colibri_weights(repo_id: str) -> dict:
    """Fetch a Colibri model's weights to the local HF cache without loading
    them — unlike _download_hf_weights, this must never route through
    transformers' from_pretrained: these repos are 4GB-1.6TB and Colibri (not
    this process) is what ever loads them into memory, via the spawned
    `coli serve` in _ensure_colibri_running."""
    try:
        from huggingface_hub import snapshot_download
    except ImportError as exc:
        raise RuntimeError(
            "huggingface_hub isn't installed — run `pip install huggingface_hub` "
            "(it's small; Colibri models don't need the full torch/transformers "
            "chat-time stack)."
        ) from exc
    snapshot_download(repo_id)
    return _model_cache_status(repo_id)


def _delete_hf_weights(repo_id: str) -> dict:
    _hf_model_cache.pop(repo_id, None)
    cache_info, repo = _hf_cache_repo(repo_id)
    if repo is not None:
        revisions = {rev.commit_hash for rev in repo.revisions}
        cache_info.delete_revisions(*revisions).execute()
    return _model_cache_status(repo_id)


_colibri_lock = threading.Lock()
_colibri_process: subprocess.Popen | None = None
_colibri_model_id: str | None = None
_colibri_log: collections.deque = collections.deque(maxlen=200)

# Large models can take a while just to start streaming experts from disk —
# generous on purpose. Polled, not slept-through: a healthy process returns
# from _ensure_colibri_running as soon as /health answers, not after a fixed
# delay.
_COLIBRI_START_TIMEOUT_S = 240.0
_COLIBRI_POLL_INTERVAL_S = 1.0
_COLIBRI_STOP_TIMEOUT_S = 5.0


def _colibri_health_ok(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/health", timeout=1) as resp:
            return resp.status == 200
    except Exception:
        return False


def _drain_colibri_output(stream) -> None:
    # Undrained output blocks the child mid-write once its pipe buffer fills
    # — same reasoning as _ResilientStream above, mirrored for the process
    # this server spawns rather than the one it's spawned by.
    try:
        for line in iter(stream.readline, ""):
            if not line:
                break
            _colibri_log.append(line.rstrip("\n"))
    except Exception:
        pass


def _stop_colibri_process() -> None:
    global _colibri_process, _colibri_model_id
    proc = _colibri_process
    _colibri_process = None
    _colibri_model_id = None
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=_COLIBRI_STOP_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=_COLIBRI_STOP_TIMEOUT_S)


def _resolve_colibri_weights_path(repo_id: str) -> str:
    from huggingface_hub import snapshot_download
    from huggingface_hub.utils import LocalEntryNotFoundError

    # local_files_only: chatting must never silently kick off a
    # multi-hundred-GB download — that's the explicit Download button on the
    # model's page (_download_colibri_weights), not a side effect of /api/chat.
    try:
        return snapshot_download(repo_id, local_files_only=True)
    except LocalEntryNotFoundError as exc:
        raise RuntimeError(
            f"weights for {repo_id!r} aren't downloaded yet — use this model's "
            "Download button first (these are large; chatting never triggers "
            "the download itself)."
        ) from exc


def _ensure_colibri_running(model_id: str, port: int) -> None:
    """Start `coli serve` for model_id if it isn't already serving it,
    blocking until /health answers or a clear error can be raised. Only one
    Colibri process runs at a time — all five families share port 8010 (see
    the README) — so switching to a different Colibri model here stops
    whatever was running first."""
    global _colibri_process, _colibri_model_id

    with _colibri_lock:
        if (
            _colibri_process is not None
            and _colibri_process.poll() is None
            and _colibri_model_id == model_id
            and _colibri_health_ok(port)
        ):
            return

        if _colibri_process is not None and _colibri_process.poll() is None:
            _stop_colibri_process()

        module = _load_model_module(model_id)
        repo_id = getattr(module, "_COLIBRI_REPO_ID", None)
        if not repo_id:
            raise RuntimeError(f"[{model_id}] has no _COLIBRI_REPO_ID configured.")
        weights_path = _resolve_colibri_weights_path(repo_id)

        coli_bin = shutil.which("coli")
        if not coli_bin:
            raise RuntimeError(
                "the `coli` engine isn't installed (or isn't on PATH) — install it once "
                "from https://github.com/JustVugg/colibri/releases, then try again."
            )

        _colibri_log.clear()
        proc = subprocess.Popen(
            [coli_bin, "serve", "--model", weights_path, "--port", str(port)],
            env={**os.environ, "COLI_MODEL": weights_path},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=_drain_colibri_output, args=(proc.stdout,), daemon=True).start()

        deadline = time.monotonic() + _COLIBRI_START_TIMEOUT_S
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                log_tail = "\n".join(_colibri_log)
                raise RuntimeError(
                    f"`coli serve` exited during startup (code {proc.returncode}).\n{log_tail}"
                )
            if _colibri_health_ok(port):
                _colibri_process = proc
                _colibri_model_id = model_id
                return
            time.sleep(_COLIBRI_POLL_INTERVAL_S)

        proc.kill()
        log_tail = "\n".join(_colibri_log)
        raise RuntimeError(
            f"`coli serve` didn't become healthy within {_COLIBRI_START_TIMEOUT_S:.0f}s.\n{log_tail}"
        )


def _colibri_generate(port: int, model_id: str, message: str, history: list | None = None) -> str:
    """Proxy a chat request to this server's own supervised Colibri instance
    (see _ensure_colibri_running, called before this from _chat_reply). A
    connection failure here is now unexpected — _ensure_colibri_running
    already confirmed /health — but is still handled without a stack trace,
    since the process could in principle die between that check and this
    request."""
    messages = _coerce_history(history) + [{"role": "user", "content": message}]
    body = json.dumps({"model": "colibri", "messages": messages}).encode("utf-8")
    req = urllib.request.Request(
        f"http://localhost:{port}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            payload = json.load(resp)
        return payload["choices"][0]["message"]["content"]
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as exc:
        return f"[{model_id}] the Colibri engine on port {port} stopped responding. ({exc})"
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        return f"[{model_id}] Colibri returned an unexpected response: {exc}"


def _chat_reply(
    model_id: str,
    message: str,
    attachments: list | None = None,
    history: list | None = None,
) -> str:
    module = _load_model_module(model_id)
    repo_id = getattr(module, "_REPO_ID", None)
    gguf = getattr(module, "_GGUF_SOURCE", None)
    external_endpoint = getattr(module, "_EXTERNAL_ENDPOINT", None)
    external_port = getattr(module, "_EXTERNAL_ENDPOINT_PORT", None)
    unsupported_reason = getattr(module, "_UNSUPPORTED_REASON", None)

    if attachments and not repo_id:
        return f"[{model_id}] doesn't accept attachments — it only takes text."

    if repo_id:
        decoded = []
        if attachments:
            try:
                decoded = _decode_attachments(attachments, _input_modalities(module))
            except AttachmentError as exc:
                return f"[{model_id}] {exc}"
        try:
            return _hf_generate(repo_id, message, decoded_attachments=decoded, history=history)
        except Exception as exc:
            reply = f"[{model_id}] failed to generate: {exc}"
            if "CUDA error" in str(exc):
                # A device-side assert corrupts the process's CUDA context;
                # every model fails from then on until a clean restart.
                reply += (
                    "\n\nA CUDA error poisons the server's GPU state — restart the "
                    "server before trying any model again."
                )
            return reply
        finally:
            _cleanup_attachments(decoded)
    if gguf:
        return (
            f"[{model_id}] runs on-device in the app (via llama.cpp), not on this server — "
            "update the app if you're seeing this message."
        )
    if external_endpoint and external_port:
        if getattr(module, "_COLIBRI_REPO_ID", None):
            try:
                _ensure_colibri_running(model_id, external_port)
            except Exception as exc:
                return f"[{model_id}] couldn't start Colibri: {exc}"
        return _colibri_generate(external_port, model_id, message, history=history)
    if unsupported_reason:
        return f"[{model_id}] isn't wired up: {unsupported_reason}."
    return f"[{model_id}] is a stub — it can't generate real responses yet. You said: {message!r}"


class _Handler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        return json.loads(raw) if raw else {}

    def do_GET(self) -> None:
        cache_match = re.fullmatch(r"/api/models/([^/]+)/cache", self.path)
        if self.path == "/api/hello":
            self._send_json(200, {"message": "Hello from the Multi-AI Cython backend"})
        elif self.path == "/api/models":
            self._send_json(200, {"models": _list_models()})
        elif self.path == "/api/device":
            self._send_json(200, hardware.detect_specs())
        elif cache_match:
            self._handle_model_route(cache_match.group(1), _model_cache_status)
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        download_match = re.fullmatch(r"/api/models/([^/]+)/download", self.path)
        if self.path == "/api/chat":
            try:
                body = self._read_json_body()
            except json.JSONDecodeError:
                self._send_json(400, {"error": "invalid JSON body"})
                return

            model = body.get("model")
            message = body.get("message", "")
            attachments = body.get("attachments") or []
            history = body.get("history") or []
            valid_ids = {m["id"] for m in _list_models()}

            if model not in valid_ids:
                self._send_json(400, {"error": f"unknown model: {model!r}"})
                return
            if not isinstance(attachments, list):
                self._send_json(400, {"error": "attachments must be a list"})
                return

            try:
                reply = _chat_reply(model, message, attachments, history)
            except Exception as exc:
                reply = f"[{model}] unexpected error: {exc}"
            self._send_json(200, {"reply": reply})
        elif download_match:
            self._handle_model_route(
                download_match.group(1), _download_hf_weights, _download_colibri_weights
            )
        else:
            self._send_json(404, {"error": "not found"})

    def do_DELETE(self) -> None:
        cache_match = re.fullmatch(r"/api/models/([^/]+)/cache", self.path)
        if cache_match:
            self._handle_model_route(cache_match.group(1), _delete_hf_weights)
        else:
            self._send_json(404, {"error": "not found"})

    def _handle_model_route(self, model_id: str, on_transformers, on_colibri=None) -> None:
        """Resolve model_id to server-managed weights and run the action for
        its kind. on_colibri defaults to on_transformers for actions (cache
        status, delete) that are already format-agnostic — see the three
        call sites below."""
        repo_id, kind, error = _resolve_server_model(model_id)
        if error:
            message, status = error
            self._send_json(status, {"error": message})
            return
        action = on_transformers if kind == "transformers" else (on_colibri or on_transformers)
        try:
            self._send_json(200, action(repo_id))
        except Exception as exc:
            self._send_json(500, {"error": str(exc)})

    def log_message(self, format: str, *args) -> None:
        pass


class _Server(ThreadingHTTPServer):
    # Fail loudly if another instance already holds the port. The default
    # (SO_REUSEADDR) lets two servers share port 8000 on Windows and split
    # traffic between them — a stale old server then answers some requests.
    allow_reuse_address = False


class _ResilientStream:
    """A stdout/stderr proxy that keeps working once its pipe is dead.

    In a packaged build the app spawns this server as a child process and
    reads its output pipes (see app/lib/backend_process.dart). If that app
    instance goes away without calling stop() — a crash, a Task Manager kill,
    an update swapping the executable — the server survives as an orphan and
    the read ends of its pipes close. The *next* app launch then finds port
    8000 answering and adopts the orphan rather than starting a fresh one, so
    the broken pipes stay in play indefinitely.

    Writing to a pipe with no reader raises OSError [Errno 22] on Windows.
    That would be harmless if nothing here wrote to stderr, but transformers
    wraps weight loading in a tqdm bar and tqdm flushes stderr while
    constructing it — so *every* model load failed with "could not load
    <repo>: [Errno 22] Invalid argument", a message with nothing in it to
    connect the failure to a closed pipe, and no way out but killing the
    orphan.

    Output is best-effort by nature here: nobody reads the backend's stderr
    in a packaged build (the app buffers it and only ever shows it if startup
    fails). Losing it is the correct trade against taking the whole process
    down with it.
    """

    def __init__(self, stream):
        self._stream = stream
        # A None stream — what a GUI-subsystem process with no console gets —
        # is simply a pipe that was dead on arrival.
        self._broken = stream is None

    # Delegated so the proxy still looks like the stream it wraps —
    # `encoding`, `buffer`, `fileno` and friends are read by libraries that
    # sniff their output destination.
    def __getattr__(self, name):
        return getattr(self._stream, name)

    def _attempt(self, name, *args):
        if self._broken:
            return None
        try:
            return getattr(self._stream, name)(*args)
        # ValueError covers "I/O operation on closed file", which is what a
        # stream closed from under us raises instead of OSError.
        except (OSError, ValueError):
            self._broken = True
            return None

    def write(self, text) -> int:
        self._attempt("write", text)
        # Claim the write succeeded regardless: callers that check the return
        # value treat a short write as an error worth retrying or raising on,
        # which is exactly what this class exists to prevent.
        return len(text)

    def flush(self) -> None:
        self._attempt("flush")

    # A dead pipe is not a terminal, and progress bars that believe they are
    # writing to one emit far more escape traffic for nobody to read.
    def isatty(self) -> bool:
        return False


def run(host: str = "localhost", port: int = 8000) -> None:
    sys.stdout = _ResilientStream(sys.stdout)
    sys.stderr = _ResilientStream(sys.stderr)
    try:
        server = _Server((host, port), _Handler)
    except OSError as exc:
        raise SystemExit(
            f"port {port} is already in use — another server instance is running. "
            f"Stop it first (or pass a different port). Original error: {exc}"
        ) from exc
    print(f"multi_ai server listening on http://{host}:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    run()

"""Minimal HTTP backend for the Flutter frontend.

Stdlib-only HTTP layer; transformers/torch are imported lazily, only when a
wired model is actually used — listing models or hitting /api/hello never
needs those heavy deps installed.

Each models/<id>.pyx declares how it runs:
  _REPO_ID        — Hugging Face checkpoint the server loads via transformers
                    (4-bit quantized on GPU so 7B+ models fit in laptop VRAM)
  _GGUF_SOURCE    — llama.cpp GGUF source; the Flutter app runs these
                    on-device via llamadart, the server never loads them
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
import importlib
import json
import os
import re
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

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


def _list_models() -> list[dict]:
    entries = []
    for path in sorted(_MODELS_DIR.glob("*.pyx")):
        stem = path.stem
        if stem in _EXCLUDED_STEMS:
            continue
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
        available = bool(repo_id or gguf)
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
        # Informational only (shown in the app's Models tab) — absent for any
        # model file that hasn't been annotated yet, never required.
        if info.get("params"):
            entry["params"] = info["params"]
        if info.get("size_gb"):
            entry["size_gb"] = info["size_gb"]
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


def _build_inputs(tokenizer, prompt: str):
    if getattr(tokenizer, "chat_template", None):
        return tokenizer.apply_chat_template(
            [{"role": "user", "content": prompt}],
            add_generation_prompt=True,
            return_dict=True,
            return_tensors="pt",
            enable_thinking=False,  # honored by Qwen-style templates, ignored by others
        )
    # Base models have no chat template; raw text would just get "continued".
    return tokenizer(f"User: {prompt}\nAssistant:", return_tensors="pt")


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


def _build_multimodal_inputs(processor, prompt: str, decoded: list[tuple[str, str]]):
    """Build one user turn whose content interleaves the attachments and the
    text, in the structured form multimodal chat templates expect."""
    content = [{"type": kind, kind: path} for kind, path in decoded]
    content.append({"type": "text", "text": prompt})
    return processor.apply_chat_template(
        [{"role": "user", "content": content}],
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
def _hf_generate(
    repo_id: str,
    prompt: str,
    max_new_tokens: int = 1024,
    decoded_attachments: list | None = None,
) -> str:
    tokenizer, model = _get_or_load_hf_model(repo_id)
    if decoded_attachments:
        # The processor owns both the chat template and the image/audio
        # preprocessing, so the text-only tokenizer path can't be reused here.
        processor = _get_or_load_processor(repo_id)
        decoder = processor if hasattr(processor, "decode") else tokenizer
        inputs = _build_multimodal_inputs(processor, prompt, decoded_attachments)
        # Pixel/audio values come out of the processor as float32; the vision
        # and audio towers run in the model's compute dtype and reject a
        # mismatch. BatchFeature.to casts only floating tensors, so token ids
        # stay integral.
        inputs = inputs.to(model.device, dtype=_compute_dtype(model))
    else:
        decoder = tokenizer
        inputs = _build_inputs(tokenizer, prompt).to(model.device)
    prompt_len = inputs["input_ids"].shape[1]
    # Never generate past the model's context window. Models with absolute
    # position embeddings (GPT-2: 1024) index off the end of the embedding
    # table otherwise — a CUDA device-side assert that corrupts the whole
    # process's GPU state, breaking every model until the server restarts.
    config = model.config
    max_pos = getattr(config, "max_position_embeddings", None)
    if max_pos is None:
        max_pos = getattr(getattr(config, "text_config", None), "max_position_embeddings", None)
    token_budget = max_new_tokens if not max_pos else min(max_new_tokens, max_pos - prompt_len)
    if token_budget <= 0:
        return "(your message is too long for this model's context window)"
    output = model.generate(
        **inputs,
        max_new_tokens=token_budget,
        do_sample=True,
        temperature=0.7,
        pad_token_id=tokenizer.pad_token_id or tokenizer.eos_token_id,
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
        return "(model returned an empty response)"
    # If it stopped only because it hit the cap (no natural end-of-turn token),
    # say so rather than ending mid-sentence with no explanation. Not when the
    # visible reply already ended cleanly at an invented User:/Assistant: turn.
    if len(new_tokens) >= token_budget and not ended_at_fake_turn:
        text += "\n\n… (response reached the length limit and was cut off)"
    return text


def _resolve_server_model(model_id: str):
    """Return (repo_id, None) or (None, (message, status)) for a model_id
    that should have server-managed weights (i.e. declares _REPO_ID)."""
    try:
        module = _load_model_module(model_id)
    except Exception:
        return None, ("unknown model", 404)
    repo_id = getattr(module, "_REPO_ID", None)
    if not repo_id:
        return None, ("model has no server-side weights to manage", 400)
    return repo_id, None


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


def _delete_hf_weights(repo_id: str) -> dict:
    _hf_model_cache.pop(repo_id, None)
    cache_info, repo = _hf_cache_repo(repo_id)
    if repo is not None:
        revisions = {rev.commit_hash for rev in repo.revisions}
        cache_info.delete_revisions(*revisions).execute()
    return _model_cache_status(repo_id)


def _chat_reply(model_id: str, message: str, attachments: list | None = None) -> str:
    module = _load_model_module(model_id)
    repo_id = getattr(module, "_REPO_ID", None)
    gguf = getattr(module, "_GGUF_SOURCE", None)
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
            return _hf_generate(repo_id, message, decoded_attachments=decoded)
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
            valid_ids = {m["id"] for m in _list_models()}

            if model not in valid_ids:
                self._send_json(400, {"error": f"unknown model: {model!r}"})
                return
            if not isinstance(attachments, list):
                self._send_json(400, {"error": "attachments must be a list"})
                return

            try:
                reply = _chat_reply(model, message, attachments)
            except Exception as exc:
                reply = f"[{model}] unexpected error: {exc}"
            self._send_json(200, {"reply": reply})
        elif download_match:
            self._handle_model_route(download_match.group(1), _download_hf_weights)
        else:
            self._send_json(404, {"error": "not found"})

    def do_DELETE(self) -> None:
        cache_match = re.fullmatch(r"/api/models/([^/]+)/cache", self.path)
        if cache_match:
            self._handle_model_route(cache_match.group(1), _delete_hf_weights)
        else:
            self._send_json(404, {"error": "not found"})

    def _handle_model_route(self, model_id: str, action) -> None:
        repo_id, error = _resolve_server_model(model_id)
        if error:
            message, status = error
            self._send_json(status, {"error": message})
            return
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


def run(host: str = "localhost", port: int = 8000) -> None:
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

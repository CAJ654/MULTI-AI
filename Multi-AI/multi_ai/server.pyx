"""Minimal HTTP backend for the Flutter frontend.

Stdlib-only HTTP layer; transformers/torch are imported lazily, only when a
wired model is actually used — listing models or hitting /api/hello never
needs those heavy deps installed.

Each models/<id>.pyx declares how it runs:
  _REPO_ID        — Hugging Face checkpoint the server loads via transformers
                    (4-bit quantized on GPU so 7B+ models fit in laptop VRAM)
  _GGUF_SOURCE    — llama.cpp GGUF source; the Flutter app runs these
                    on-device via llamadart, the server never loads them
  _UNSUPPORTED_REASON — not runnable here; /api/chat explains why

Prompts go through the tokenizer's chat template when it has one — feeding
raw text to an instruct model makes it "continue" your sentence instead of
answering it, which looks like hallucination. Template-less base models
(e.g. GPT-2) get a plain User:/Assistant: framing and honest labeling.

Weights download on first use and stay cached in ~/.cache/huggingface.
If every HTTPS request fails with CERTIFICATE_VERIFY_FAILED, see the README
note about pip-system-certs.
"""
from __future__ import annotations

import importlib
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_MODELS_DIR = Path(__file__).resolve().parent / "models"
# TensorFlow/pytorch are framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}

_model_module_cache: dict[str, object] = {}
_hf_model_cache: dict[str, tuple] = {}


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
        available = bool(repo_id or gguf)
        entry = {
            "id": stem,
            "name": name if available else f"{name} (unavailable)",
            "available": available,
        }
        if gguf:
            entry["gguf"] = gguf
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
    gc.collect()
    try:
        import torch

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except ImportError:
        pass


# A cap, not a target: the model still stops early at its end-of-turn token,
# so short answers stay fast. This just keeps long ones (lists, code) from
# being truncated mid-sentence.
def _hf_generate(repo_id: str, prompt: str, max_new_tokens: int = 1024) -> str:
    if repo_id not in _hf_model_cache:
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
            raise RuntimeError(
                f"could not load {repo_id}: {exc}. Gated repos need a Hugging Face access "
                "token — run `huggingface-cli login` or set HF_TOKEN."
            ) from exc
        _hf_model_cache[repo_id] = (tokenizer, model)

    tokenizer, model = _hf_model_cache[repo_id]
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
    text = tokenizer.decode(new_tokens, skip_special_tokens=True)
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


def _chat_reply(model_id: str, message: str) -> str:
    module = _load_model_module(model_id)
    repo_id = getattr(module, "_REPO_ID", None)
    gguf = getattr(module, "_GGUF_SOURCE", None)
    unsupported_reason = getattr(module, "_UNSUPPORTED_REASON", None)

    if repo_id:
        try:
            return _hf_generate(repo_id, message)
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
        if self.path == "/api/hello":
            self._send_json(200, {"message": "Hello from the Multi-AI Cython backend"})
        elif self.path == "/api/models":
            self._send_json(200, {"models": _list_models()})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/api/chat":
            self._send_json(404, {"error": "not found"})
            return

        try:
            body = self._read_json_body()
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid JSON body"})
            return

        model = body.get("model")
        message = body.get("message", "")
        valid_ids = {m["id"] for m in _list_models()}

        if model not in valid_ids:
            self._send_json(400, {"error": f"unknown model: {model!r}"})
            return

        try:
            reply = _chat_reply(model, message)
        except Exception as exc:
            reply = f"[{model}] unexpected error: {exc}"
        self._send_json(200, {"reply": reply})

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

"""Exercises multi_ai.server's generation pipeline (_get_or_load_hf_model,
_hf_generate, _chat_reply and friends) against fake torch/transformers
modules, instead of real weights.

Every server-side model funnels through this same shared pipeline, and it's
exactly where the historical breakage lived (see the README's 2026-06/07 fix
log: gated repos, "quantized" checkpoint clashes, multimodal config
fallbacks, the CUDA-poisoning bug). Downloading real weights for all ~20
server-side models to test this would cost 270+ GB and an hour of generation
time per run — not viable. Faking torch/transformers instead lets these
tests drive every branch of the pipeline for free, in milliseconds, with no
network and no GPU.

What this does NOT catch: a specific checkpoint's tokenizer/template quirks,
or whether a model's *actual* output is any good. Those still need a real
run. This is a regression net for the plumbing every model shares, not a
substitute for trying a model once.

Run directly: python Multi-AI/tests/test_generation_pipeline.pyx
"""
from __future__ import annotations

import importlib
import sys
import types

import pytest


def _server():
    return importlib.import_module("multi_ai.server")


class _FakeTensor:
    """Stands in for a 1-D torch.Tensor of token ids (batch size 1)."""

    def __init__(self, ids):
        self.data = list(ids)

    @property
    def shape(self):
        return (1, len(self.data))

    def __getitem__(self, idx):
        if isinstance(idx, slice):
            return _FakeTensor(self.data[idx])
        return self.data[idx]

    def __len__(self):
        return len(self.data)


class _FakeBatch(dict):
    """Stands in for a BatchEncoding: dict-like, plus a no-op .to(device)."""

    def to(self, device):
        return self


class _FakeConfig:
    def __init__(self, max_position_embeddings=None, text_config=None):
        self.max_position_embeddings = max_position_embeddings
        self.text_config = text_config


class _FakeTokenizer:
    def __init__(self, chat_template="tpl", decode_fn=None, prompt_ids=(10, 11, 12)):
        self.chat_template = chat_template
        self.pad_token_id = 0
        self.eos_token_id = 2
        self._decode_fn = decode_fn or (lambda ids: f"reply:{ids}")
        self._prompt_ids = list(prompt_ids)
        # What the last template/plain-text call actually saw — lets tests
        # assert which conversation turns reached the model.
        self.last_messages = None
        self.last_text = None

    def apply_chat_template(self, messages, **kwargs):
        self.last_messages = messages
        # tokenize=True (the token-counting path in _fit_history) wants a bare
        # sequence of ids; the prompt-building path wants the batch dict.
        if kwargs.get("tokenize") and not kwargs.get("return_dict"):
            return list(self._prompt_ids) * max(1, len(messages))
        return _FakeBatch(input_ids=_FakeTensor(self._prompt_ids))

    def __call__(self, text, return_tensors=None, **kwargs):
        self.last_text = text
        return _FakeBatch(input_ids=_FakeTensor(self._prompt_ids))

    def decode(self, tokens, skip_special_tokens=True):
        ids = tokens.data if hasattr(tokens, "data") else list(tokens)
        return self._decode_fn(ids)


class _FakeModel:
    def __init__(self, config, reply_token_ids=None, hit_cap=False, raise_exc=None):
        self.config = config
        self.device = "cpu"
        self._reply_token_ids = reply_token_ids
        self._hit_cap = hit_cap
        self._raise_exc = raise_exc

    def generate(self, **kwargs):
        if self._raise_exc:
            raise self._raise_exc
        # Kept so tests can assert on what was actually passed to generate —
        # pad_token_id and the reply budget are both decided by the caller.
        self.last_kwargs = dict(kwargs)
        input_ids = kwargs["input_ids"]
        max_new_tokens = kwargs["max_new_tokens"]
        if self._reply_token_ids is not None:
            suffix = list(self._reply_token_ids)
        elif self._hit_cap:
            suffix = [7] * max_new_tokens
        else:
            suffix = [7, 8, 9][: max(1, min(3, max_new_tokens))]
        return [_FakeTensor(list(input_ids.data) + suffix)]


def _install_fakes(monkeypatch, *, cuda_available=False, model_factory, tokenizer_factory=None):
    """Wires fake torch/transformers into sys.modules for the duration of one
    test, and clears the server's model cache so a repo_id reused by an
    earlier test can't leak that test's fake model into this one."""
    server = _server()
    monkeypatch.setattr(server, "_hf_model_cache", {})

    fake_torch = types.ModuleType("torch")
    fake_torch.cuda = types.SimpleNamespace(
        is_available=lambda: cuda_available, empty_cache=lambda: None
    )
    fake_torch.bfloat16 = "bfloat16"

    fake_transformers = types.ModuleType("transformers")

    class _AutoTokenizer:
        @staticmethod
        def from_pretrained(repo_id, local_files_only=False, **kwargs):
            if tokenizer_factory is not None:
                return tokenizer_factory(local_files_only=local_files_only)
            return _FakeTokenizer()

    class _AutoModelForCausalLM:
        @staticmethod
        def from_pretrained(repo_id, local_files_only=False, **kwargs):
            return model_factory(local_files_only=local_files_only, **kwargs)

    class _AutoModelForImageTextToText:
        @staticmethod
        def from_pretrained(repo_id, local_files_only=False, **kwargs):
            return _FakeModel(_FakeConfig(max_position_embeddings=4096))

    class _BitsAndBytesConfig:
        def __init__(self, **kwargs):
            pass

    fake_transformers.AutoTokenizer = _AutoTokenizer
    fake_transformers.AutoModelForCausalLM = _AutoModelForCausalLM
    fake_transformers.AutoModelForImageTextToText = _AutoModelForImageTextToText
    fake_transformers.BitsAndBytesConfig = _BitsAndBytesConfig

    monkeypatch.setitem(sys.modules, "torch", fake_torch)
    monkeypatch.setitem(sys.modules, "transformers", fake_transformers)
    return server


def test_chat_template_flow_generates_a_reply(monkeypatch):
    """The common case: an instruct model with a chat template loads and
    generates without hitting real weights."""
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
    )
    reply = server._chat_reply("gemma1", "Hello, how are you?")
    assert reply == "reply:[7, 8, 9]"


def test_base_model_flow_truncates_invented_turns(monkeypatch):
    """Template-less base models get "User:/Assistant:" framing, and the model
    then invents further turns that must be cut.

    Driven through falcon_mamba_7b, the roster's remaining base model — GPT-2
    used to be the example, but it was removed for being unable to converse.
    The fake tokenizer's chat_template=None is what actually selects this path.
    """
    decode_fn = lambda ids: "Paris.\nUser: what about Spain?\nAssistant: Madrid."
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
        tokenizer_factory=lambda local_files_only: _FakeTokenizer(
            chat_template=None, decode_fn=decode_fn
        ),
    )
    reply = server._chat_reply("falcon_mamba_7b", "What is the capital of France?")
    assert reply == "Paris."


def test_context_window_exhausted_returns_friendly_message(monkeypatch):
    """A prompt at (or past) the model's context window must not be sent to
    generate() at all — real code did this wrong once and corrupted CUDA."""
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=3)),
    )
    reply = server._chat_reply("gemma1", "Hello, how are you?")
    assert reply == "(your message is too long for this model's context window)"


def test_length_cap_notes_the_response_was_cut_off(monkeypatch):
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(
            _FakeConfig(max_position_embeddings=15), hit_cap=True
        ),
    )
    reply = server._chat_reply("gemma1", "Hello, how are you?")
    assert reply.endswith("(response reached the length limit and was cut off)")


def test_reasoning_tags_are_stripped(monkeypatch):
    """DeepSeek-R1/Qwen-style <think> deliberation must not leak into the
    visible reply."""
    decode_fn = lambda ids: "<think>the user wants a greeting</think>Hello!"
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
        tokenizer_factory=lambda local_files_only: _FakeTokenizer(decode_fn=decode_fn),
    )
    reply = server._chat_reply("gemma1", "Hi")
    assert reply == "Hello!"


def test_prequantized_checkpoint_retries_without_our_quantization(monkeypatch):
    """Ministral-3-style FP8 checkpoints reject having a 4-bit
    quantization_config stacked on top; the loader must retry without one
    instead of failing outright."""

    def model_factory(*, local_files_only, **kwargs):
        if "quantization_config" in kwargs:
            raise ValueError("weights are already quantized in safetensors format")
        return _FakeModel(_FakeConfig(max_position_embeddings=4096))

    server = _install_fakes(monkeypatch, cuda_available=True, model_factory=model_factory)
    reply = server._chat_reply("ministral_3_8b", "Hello")
    assert reply == "reply:[7, 8, 9]"


def test_multimodal_config_falls_back_to_image_text_class(monkeypatch):
    """Vision-language checkpoints (e.g. Ministral 3) raise on
    AutoModelForCausalLM; the loader must retry via
    AutoModelForImageTextToText instead of surfacing the error."""

    def model_factory(*, local_files_only, **kwargs):
        raise ValueError(
            "Unrecognized configuration class <Mistral3Config> for this kind of "
            "AutoModel: AutoModelForCausalLM."
        )

    server = _install_fakes(monkeypatch, model_factory=model_factory)
    reply = server._chat_reply("ministral_3_8b", "Hello")
    assert reply == "reply:[7, 8, 9]"


def test_local_cache_miss_falls_back_to_network_load(monkeypatch):
    """from_pretrained(local_files_only=True) missing the cache must retry
    with network access, not fail outright."""

    def model_factory(*, local_files_only, **kwargs):
        if local_files_only:
            raise OSError("not found in local cache")
        return _FakeModel(_FakeConfig(max_position_embeddings=4096))

    server = _install_fakes(monkeypatch, model_factory=model_factory)
    reply = server._chat_reply("gemma1", "Hello")
    assert reply == "reply:[7, 8, 9]"


def test_cuda_error_during_generation_adds_restart_warning(monkeypatch):
    """A CUDA device-side assert poisons the whole process's GPU state — the
    reply must say so instead of just showing the raw exception."""
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(
            _FakeConfig(max_position_embeddings=4096),
            raise_exc=RuntimeError("CUDA error: device-side assert triggered"),
        ),
    )
    reply = server._chat_reply("gemma1", "Hello")
    assert reply.startswith("[gemma1] failed to generate:")
    assert "restart the server" in reply


def test_unreachable_repo_gives_actionable_error(monkeypatch):
    """A gated/renamed/unreachable repo must produce a message pointing at
    the fix (HF_TOKEN / huggingface-cli login), not an opaque traceback."""

    def tokenizer_factory(local_files_only):
        raise Exception("401 Client Error: gated repo, access denied")

    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
        tokenizer_factory=tokenizer_factory,
    )
    reply = server._chat_reply("gemma1", "Hello")
    assert reply.startswith("[gemma1] failed to generate: could not load")
    assert "Hugging Face access token" in reply


# ------------------------------------------------------- conversation history


def test_history_reaches_the_model(monkeypatch):
    """Prior turns must be in the prompt, oldest first, with the new message
    last. Without this every reply is answered as if it were the first — the
    UI shows a thread, so a stateless model looks like it's hallucinating."""
    tokenizer = _FakeTokenizer()
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
        tokenizer_factory=lambda local_files_only: tokenizer,
    )
    server._chat_reply(
        "gemma1",
        "What is my name?",
        history=[
            {"role": "user", "content": "My name is Alex."},
            {"role": "assistant", "content": "Nice to meet you, Alex."},
        ],
    )
    assert [m["role"] for m in tokenizer.last_messages] == ["user", "assistant", "user"]
    assert tokenizer.last_messages[0]["content"] == "My name is Alex."
    assert tokenizer.last_messages[-1]["content"] == "What is my name?"


def test_history_without_turns_is_unchanged(monkeypatch):
    """A first message must produce exactly the single-turn prompt it always
    did — history is additive, not a rewrite of the existing path."""
    tokenizer = _FakeTokenizer()
    server = _install_fakes(
        monkeypatch,
        model_factory=lambda **kw: _FakeModel(_FakeConfig(max_position_embeddings=4096)),
        tokenizer_factory=lambda local_files_only: tokenizer,
    )
    server._chat_reply("gemma1", "Hello")
    assert tokenizer.last_messages == [{"role": "user", "content": "Hello"}]


def test_malformed_history_entries_are_dropped():
    """A corrupt entry should cost the model some context, not fail the whole
    request — the client's transcript is not a trusted schema."""
    server = _server()
    coerced = server._coerce_history(
        [
            {"role": "user", "content": "keep me"},
            {"role": "system", "content": "wrong role"},
            {"role": "user", "content": ""},  # blank
            {"role": "assistant"},  # no content
            "not a dict",
            {"role": "assistant", "content": "keep me too"},
        ]
    )
    assert coerced == [
        {"role": "user", "content": "keep me"},
        {"role": "assistant", "content": "keep me too"},
    ]
    assert server._coerce_history(None) == []
    assert server._coerce_history("nope") == []


def test_history_trims_oldest_turns_to_fit_budget():
    """Over budget, the oldest turns go first so the newest exchange — the
    part the reply actually depends on — is what survives."""
    server = _server()
    tokenizer = _FakeTokenizer(prompt_ids=(1, 2, 3, 4, 5))  # 5 "tokens" per message
    turns = [
        {"role": "user", "content": "oldest"},
        {"role": "assistant", "content": "older reply"},
        {"role": "user", "content": "newest"},
    ]
    # Budget fits one turn's worth (5) but not three (15).
    kept = server._fit_history(tokenizer, turns, budget=7)
    assert kept == [{"role": "user", "content": "newest"}]
    # A budget of zero disables history entirely rather than erroring.
    assert server._fit_history(tokenizer, turns, budget=0) == []


def test_history_never_opens_on_an_assistant_turn():
    """Trimming must not leave a reply with no question above it — that reads
    as the model talking to itself and derails the next answer."""
    server = _server()
    tokenizer = _FakeTokenizer(prompt_ids=(1, 2, 3, 4, 5))
    turns = [
        {"role": "user", "content": "q1"},
        {"role": "assistant", "content": "a1"},
        {"role": "assistant", "content": "a1 continued"},
        {"role": "user", "content": "q2"},
    ]
    kept = server._fit_history(tokenizer, turns, budget=12)
    assert kept and kept[0]["role"] == "user"


def test_history_budget_reserves_room_for_the_reply():
    """History must not crowd out the answer it was meant to inform: on a
    small context window the budget shrinks to fit prompt + reply."""
    server = _server()
    tokenizer = _FakeTokenizer(prompt_ids=(1, 2, 3))  # 3-token prompt
    model = _FakeModel(_FakeConfig(max_position_embeddings=1024))
    budget = server._history_budget(model, tokenizer, "hi", reply_reserve=1000)
    assert budget == 1024 - 3 - 1000
    # A window too small for prompt+reply leaves no room at all, rather than
    # going negative and being treated as unlimited.
    tiny = _FakeModel(_FakeConfig(max_position_embeddings=64))
    assert server._history_budget(tiny, tokenizer, "hi", reply_reserve=1000) == 0


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))

"""Exercises multi_ai.server's OpenAI-compatible helpers (_openai_chat_request,
_openai_completion, _openai_sse_events) — the translation layer behind
POST /v1/chat/completions that lets opencode, LibreChat and other
OpenAI-speaking clients use the server-side models.

Only the pure request/response mapping is covered; the HTTP handler itself is
a thin wrapper around these plus _chat_reply, which test_generation_pipeline
already drives.

Run directly: python Multi-AI/tests/test_openai_route.pyx
"""
from __future__ import annotations

import importlib
import json

import pytest


def _server():
    return importlib.import_module("multi_ai.server")


@pytest.fixture(autouse=True)
def _roster(monkeypatch):
    server = _server()
    monkeypatch.setattr(
        server,
        "_list_models",
        lambda: [
            {"id": "server_model", "available": True},
            {"id": "on_device_model", "available": True, "gguf": "x/y"},
            {"id": "broken_model", "available": False},
        ],
    )


def _body(messages, model="server_model"):
    return {"model": model, "messages": messages}


def test_maps_last_user_turn_and_prior_history():
    model, message, history, error = _server()._openai_chat_request(
        _body([
            {"role": "user", "content": "hi"},
            {"role": "assistant", "content": "hello"},
            {"role": "user", "content": "and now?"},
        ])
    )
    assert error is None
    assert model == "server_model"
    assert message == "and now?"
    assert history == [
        {"role": "user", "content": "hi"},
        {"role": "assistant", "content": "hello"},
    ]


def test_system_text_is_folded_into_the_final_user_turn():
    _, message, history, error = _server()._openai_chat_request(
        _body([
            {"role": "system", "content": "Be terse."},
            {"role": "user", "content": "hi"},
        ])
    )
    assert error is None
    assert message == "Be terse.\n\nhi"
    assert history == []


def test_content_parts_keep_only_text():
    _, message, _, error = _server()._openai_chat_request(
        _body([
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "look"},
                    {"type": "image_url", "image_url": {"url": "data:..."}},
                    {"type": "text", "text": "here"},
                ],
            }
        ])
    )
    assert error is None
    assert message == "look\nhere"


@pytest.mark.parametrize("model", ["on_device_model", "broken_model", "nope", None])
def test_rejects_models_the_server_cannot_run(model):
    _, _, _, error = _server()._openai_chat_request(
        _body([{"role": "user", "content": "hi"}], model=model)
    )
    assert error is not None


@pytest.mark.parametrize(
    "messages",
    [
        None,
        [],
        "hi",
        [{"role": "assistant", "content": "last turn is not the user's"}],
        [{"role": "system", "content": "only a system prompt"}],
    ],
)
def test_rejects_malformed_message_lists(messages):
    _, _, _, error = _server()._openai_chat_request(_body(messages))
    assert error is not None


def test_rejects_non_object_body():
    assert _server()._openai_chat_request([1, 2])[3] is not None


def test_completion_shape():
    out = _server()._openai_completion("server_model", "pong", "chatcmpl-1", 123)
    assert out["object"] == "chat.completion"
    assert out["choices"][0]["message"] == {"role": "assistant", "content": "pong"}
    assert out["choices"][0]["finish_reason"] == "stop"


def test_sse_events_reassemble_to_the_reply():
    events = _server()._openai_sse_events("server_model", "pong", "chatcmpl-1", 123)
    assert events[-1] == b"data: [DONE]\n\n"
    chunks = [json.loads(e[len(b"data: "):]) for e in events[:-1]]
    assert chunks[0]["choices"][0]["delta"] == {"role": "assistant"}
    assert "".join(c["choices"][0]["delta"].get("content", "") for c in chunks) == "pong"
    assert chunks[-1]["choices"][0]["finish_reason"] == "stop"
    assert all(c["object"] == "chat.completion.chunk" for c in chunks)

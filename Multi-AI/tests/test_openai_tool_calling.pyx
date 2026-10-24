"""Exercises the tool-calling half of multi_ai.server's OpenAI route: the
request mapping (_openai_tools, _openai_tool_messages, _openai_agent_request),
the generation-side helpers (_parse_tool_calls, _fit_messages,
_hf_generate_chat, _chat_reply_with_tools) and the response shapes for a turn
that ends in tool calls.

Generation is driven against a fake tokenizer and model, like
test_generation_pipeline.pyx — this checks the plumbing, not whether a real
checkpoint's template and output cooperate. That still needs a real run.

Run directly: python Multi-AI/tests/test_openai_tool_calling.pyx
"""
from __future__ import annotations

import importlib
import json

import pytest


def _server():
    return importlib.import_module("multi_ai.server")


_TOOLS = [
    {"type": "function", "function": {"name": "read", "description": "read a file", "parameters": {}}},
    {"type": "function", "function": {"name": "bash", "description": "run a command", "parameters": {}}},
]
_NAMES = {"read", "bash"}


@pytest.fixture(autouse=True)
def _roster(monkeypatch):
    monkeypatch.setattr(
        _server(),
        "_list_models",
        lambda: [
            {"id": "server_model", "available": True},
            {"id": "on_device_model", "available": True, "gguf": "x/y"},
        ],
    )


# ----------------------------------------------------------------- parsing


def test_parses_hermes_tool_call_blocks():
    text, calls = _server()._parse_tool_calls(
        'Let me look.\n<tool_call>\n{"name": "read", "arguments": {"path": "a.py"}}\n</tool_call>'
        '<tool_call>{"name": "bash", "arguments": {"command": "ls"}}</tool_call>',
        _NAMES,
    )
    assert text == "Let me look."
    assert calls == [
        {"name": "read", "arguments": {"path": "a.py"}},
        {"name": "bash", "arguments": {"command": "ls"}},
    ]


def test_parses_llama_style_bare_json_with_parameters():
    text, calls = _server()._parse_tool_calls('{"name": "read", "parameters": {"path": "a.py"}}', _NAMES)
    assert text == ""
    assert calls == [{"name": "read", "arguments": {"path": "a.py"}}]


def test_parses_mistral_style_list_after_prefix():
    _, calls = _server()._parse_tool_calls(
        '[TOOL_CALLS][{"name": "bash", "arguments": {"command": "ls"}}]', _NAMES
    )
    assert calls == [{"name": "bash", "arguments": {"command": "ls"}}]


def test_arguments_given_as_a_json_string_are_decoded():
    _, calls = _server()._parse_tool_calls(
        '<tool_call>{"name": "read", "arguments": "{\\"path\\": \\"a.py\\"}"}</tool_call>', _NAMES
    )
    assert calls == [{"name": "read", "arguments": {"path": "a.py"}}]


@pytest.mark.parametrize(
    "text",
    [
        "Just an answer.",
        '{"name": "not_a_tool", "arguments": {}}',
        '{"name": "Alice", "age": 3}',
        '<tool_call>{"name": "ghost", "arguments": {}}</tool_call>',
        "<tool_call>{broken</tool_call>",
        '[{"name": "read", "arguments": {}}, {"name": "ghost", "arguments": {}}]',
    ],
)
def test_text_that_is_not_a_known_tool_call_is_left_alone(text):
    out, calls = _server()._parse_tool_calls(text, _NAMES)
    assert calls == []
    assert out == text


# ---------------------------------------------------------- request mapping


def test_tools_are_ignored_for_tool_choice_none_and_malformed_entries():
    s = _server()
    assert s._openai_tools({"tools": _TOOLS}) == _TOOLS
    assert s._openai_tools({"tools": _TOOLS, "tool_choice": "none"}) == []
    assert s._openai_tools({"tools": "x"}) == []
    assert s._openai_tools({"tools": [{"type": "function"}, {"function": {"name": ""}}, 3]}) == []
    assert s._openai_tools({}) == []


def test_tool_messages_keep_roles_and_decode_call_arguments():
    msgs = _server()._openai_tool_messages([
        {"role": "system", "content": "sys"},
        {"role": "user", "content": "go"},
        {
            "role": "assistant",
            "content": None,
            "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "read", "arguments": '{"path": "a.py"}'}}
            ],
        },
        {"role": "tool", "tool_call_id": "c1", "content": "file body"},
    ])
    assert msgs == [
        {"role": "system", "content": "sys"},
        {"role": "user", "content": "go"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "read", "arguments": {"path": "a.py"}}}
            ],
        },
        {"role": "tool", "content": "file body", "tool_call_id": "c1", "name": "read"},
    ]


def test_agent_request_may_end_on_a_tool_result():
    model, messages, tools, error = _server()._openai_agent_request({
        "model": "server_model",
        "tools": _TOOLS,
        "messages": [
            {"role": "user", "content": "go"},
            {"role": "assistant", "tool_calls": [{"id": "c1", "function": {"name": "read", "arguments": "{}"}}]},
            {"role": "tool", "tool_call_id": "c1", "content": "ok"},
        ],
    })
    assert error is None
    assert model == "server_model"
    assert messages[-1]["role"] == "tool"
    assert tools == _TOOLS


def test_agent_request_rejects_ending_on_an_assistant_turn_and_non_server_models():
    s = _server()
    assert s._openai_agent_request(
        {"model": "server_model", "messages": [{"role": "assistant", "content": "hi"}]}
    )[3] is not None
    assert s._openai_agent_request(
        {"model": "on_device_model", "messages": [{"role": "user", "content": "hi"}]}
    )[3] is not None


# --------------------------------------------------------------- generation


class _Ids(list):
    @property
    def shape(self):
        return (1, len(self))


class _Batch(dict):
    def __init__(self, ids):
        super().__init__(input_ids=_Ids(ids))

    def to(self, device):
        return self


class _CountingTokenizer:
    """One token per character of content, so budgets are easy to reason about."""

    chat_template = "tpl"
    pad_token_id = 0
    eos_token_id = 2
    reply = ""

    def __init__(self):
        self.template_calls = []

    def apply_chat_template(self, messages, tools=None, **kwargs):
        self.template_calls.append({"messages": messages, "tools": tools, **kwargs})
        ids = [1] * (sum(len(m.get("content") or "") for m in messages) + (len(str(tools)) if tools else 0))
        return _Batch(ids) if kwargs.get("return_dict") else ids

    def decode(self, ids, skip_special_tokens=False):
        return self.reply


def _msg(role, content="x" * 10, **extra):
    return {"role": role, "content": content, **extra}


def test_fit_messages_drops_oldest_user_groups_but_never_system():
    tok = _CountingTokenizer()
    messages = [
        _msg("system"),
        _msg("user"), _msg("assistant"),
        _msg("user"), _msg("assistant"),
        _msg("user"),
    ]
    # Whole conversation is 60 tokens. Dropping the oldest group leaves 40,
    # still over 35; dropping the next leaves system + the final user = 20.
    fitted = _server()._fit_messages(tok, messages, [], budget=35)
    assert [m["role"] for m in fitted] == ["system", "user"]
    assert fitted[-1] is messages[-1]


def test_fit_messages_trims_old_steps_inside_one_task_but_keeps_the_task_and_newest_step():
    tok = _CountingTokenizer()
    messages = [
        _msg("user", "task"),
        _msg("assistant", "step1", tool_calls=[{"id": "a"}]), _msg("tool", "r1"),
        _msg("assistant", "step2", tool_calls=[{"id": "b"}]), _msg("tool", "r2"),
        _msg("assistant", "step3", tool_calls=[{"id": "c"}]), _msg("tool", "r3"),
    ]
    fitted = _server()._fit_messages(tok, messages, [], budget=0)
    # Nothing fits a zero budget, so it trims as far as it safely can and stops.
    assert [m["content"] for m in fitted] == ["task", "step3", "r3"]


def test_fit_messages_leaves_a_conversation_that_already_fits_alone():
    tok = _CountingTokenizer()
    messages = [_msg("system"), _msg("user"), _msg("assistant"), _msg("user")]
    assert _server()._fit_messages(tok, messages, [], budget=10_000) == messages


class _Model:
    device = "cpu"
    config = type("C", (), {"max_position_embeddings": 100000, "text_config": None})()

    def generate(self, **kwargs):
        return [list(kwargs["input_ids"]) + [5, 6, 7]]


def test_hf_generate_chat_templates_with_tools_and_returns_the_text(monkeypatch):
    s = _server()
    tok = _CountingTokenizer()
    tok.reply = '<tool_call>{"name": "read", "arguments": {"path": "a.py"}}</tool_call>'
    monkeypatch.setattr(s, "_get_or_load_hf_model", lambda repo: (tok, _Model()))
    text = s._hf_generate_chat("repo", [_msg("user", "go")], _TOOLS)
    assert text == tok.reply
    final = tok.template_calls[-1]
    assert final["tools"] == _TOOLS
    assert final["add_generation_prompt"] is True
    assert final["return_dict"] is True


def test_hf_generate_chat_refuses_a_model_with_no_chat_template(monkeypatch):
    s = _server()
    tok = _CountingTokenizer()
    tok.chat_template = None
    monkeypatch.setattr(s, "_get_or_load_hf_model", lambda repo: (tok, _Model()))
    with pytest.raises(ValueError):
        s._hf_generate_chat("repo", [_msg("user", "go")], _TOOLS)


def test_chat_reply_with_tools_returns_parsed_calls_with_ids(monkeypatch):
    s = _server()
    module = type("M", (), {"_REPO_ID": "repo"})
    monkeypatch.setattr(s, "_load_model_module", lambda model_id: module)
    monkeypatch.setattr(
        s, "_hf_generate_chat",
        lambda repo, messages, tools: 'ok <tool_call>{"name": "bash", "arguments": {"command": "ls"}}</tool_call>',
    )
    text, calls = s._chat_reply_with_tools("server_model", [_msg("user", "go")], _TOOLS)
    assert text == "ok"
    assert calls[0]["name"] == "bash"
    assert calls[0]["id"].startswith("call_")


def test_chat_reply_with_tools_reports_a_generation_failure_as_text(monkeypatch):
    s = _server()
    module = type("M", (), {"_REPO_ID": "repo"})
    monkeypatch.setattr(s, "_load_model_module", lambda model_id: module)

    def boom(*args):
        raise RuntimeError("out of memory")

    monkeypatch.setattr(s, "_hf_generate_chat", boom)
    text, calls = s._chat_reply_with_tools("server_model", [_msg("user", "go")], _TOOLS)
    assert "out of memory" in text
    assert calls == []


def test_a_non_transformers_model_falls_back_to_plain_chat_without_calls(monkeypatch):
    s = _server()
    module = type("M", (), {})
    seen = {}

    def fake_reply(model_id, message, attachments, history):
        seen.update(message=message, history=history)
        return "plain"

    monkeypatch.setattr(s, "_load_model_module", lambda model_id: module)
    monkeypatch.setattr(s, "_chat_reply", fake_reply)
    text, calls = s._chat_reply_with_tools(
        "server_model",
        [_msg("system", "sys"), _msg("user", "hi"), _msg("assistant", "yo"), _msg("user", "again")],
        _TOOLS,
    )
    assert (text, calls) == ("plain", [])
    assert seen["message"] == "sys\n\nagain"
    assert seen["history"] == [_msg("user", "hi"), _msg("assistant", "yo")]


# ---------------------------------------------------------------- responses


def test_completion_with_tool_calls_uses_the_wire_shape():
    calls = [{"id": "call_1", "name": "read", "arguments": {"path": "a.py"}}]
    out = _server()._openai_completion("server_model", "", "chatcmpl-1", 123, calls)
    choice = out["choices"][0]
    assert choice["finish_reason"] == "tool_calls"
    assert choice["message"]["content"] is None
    assert choice["message"]["tool_calls"] == [
        {"id": "call_1", "type": "function", "function": {"name": "read", "arguments": '{"path": "a.py"}'}}
    ]


def test_sse_with_tool_calls_sends_each_call_whole_and_finishes_with_tool_calls():
    calls = [{"id": "call_1", "name": "read", "arguments": {"path": "a.py"}}]
    events = _server()._openai_sse_events("server_model", "", "chatcmpl-1", 123, calls)
    chunks = [json.loads(e[len(b"data: "):]) for e in events[:-1]]
    deltas = [c["choices"][0]["delta"] for c in chunks]
    assert not any("content" in d for d in deltas)
    sent = next(d["tool_calls"] for d in deltas if "tool_calls" in d)
    assert sent == [
        {"index": 0, "id": "call_1", "type": "function",
         "function": {"name": "read", "arguments": '{"path": "a.py"}'}}
    ]
    assert chunks[-1]["choices"][0]["finish_reason"] == "tool_calls"

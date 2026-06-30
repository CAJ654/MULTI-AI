"""Minimal HTTP backend for the Flutter frontend.

Stdlib-only so it has no dependency on the heavier model stubs (torch,
tensorflow, etc.) under models/ — just enough for the app to have real
endpoints to call instead of erroring out with "connection refused".

The models under models/ are placeholder stubs with no real inference
(see README TODO), so /api/chat returns an honest canned reply rather
than pretending to run a model.
"""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_MODELS_DIR = Path(__file__).resolve().parent / "models"
# TensorFlow/pytorch are framework helper stubs, not chat models.
_EXCLUDED_STEMS = {"__init__", "TensorFlow", "pytorch"}


def _list_models() -> list[dict]:
    stems = sorted(p.stem for p in _MODELS_DIR.glob("*.pyx") if p.stem not in _EXCLUDED_STEMS)
    return [{"id": stem, "name": stem.replace("_", " ")} for stem in stems]


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

        reply = f"[{model}] is a stub — it can't generate real responses yet. You said: {message!r}"
        self._send_json(200, {"reply": reply})

    def log_message(self, format: str, *args) -> None:
        pass


def run(host: str = "localhost", port: int = 8000) -> None:
    server = ThreadingHTTPServer((host, port), _Handler)
    print(f"multi_ai server listening on http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    run()

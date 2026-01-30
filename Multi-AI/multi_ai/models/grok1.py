"""grok1 stub inside package."""

from transformers import AutoModelForCausalLM

__version__ = "0.1.0"

def get_info():
    return {"name": "grok-1", "version": __version__}


def grok(text: str) -> str:
    if not text:
        return "(nothing to grok)"
    s = text.strip()
    return f"GROKED[{len(s)}]: {s[:60]}" if len(s) > 0 else "(empty)"

if __name__ == "__main__":
    print(get_info())
    print(grok("Example input to grok-1"))

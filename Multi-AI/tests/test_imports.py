import importlib


def test_models_importable():
    names = [
        "multi_ai.models.deepmind",
        "multi_ai.models.deepmind_v3",
        "multi_ai.models.deepseek_v3",
        "multi_ai.models.deepseek_r1",
        "multi_ai.models.kimi_k2",
        "multi_ai.models.qwen3",
        "multi_ai.models.pytorch",
        "multi_ai.models.grok1",
    ]
    for nm in names:
        mod = importlib.import_module(nm)
        assert hasattr(mod, "get_info")

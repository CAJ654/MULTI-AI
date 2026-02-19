"""pyTorch helper stub inside package."""

import torch

__version__ = "0.1.0"

def get_info():
    return {"name": "pyTorch", "version": __version__}


def is_torch_available() -> bool:
    try:
        import torch  # type: ignore
        return True
    except Exception:
        return False


def tensor_example():
    if is_torch_available():
        import torch  # type: ignore
        t = torch.arange(0, 5)
        return {"type": "torch", "value": t, "doubled": t * 2}
    try:
        import numpy as np  # type: ignore
        a = np.arange(5)
        return {"type": "numpy", "value": a, "doubled": a * 2}
    except Exception:
        lst = list(range(5))
        return {"type": "list", "value": lst, "doubled": [x * 2 for x in lst]}

if __name__ == "__main__":
    print(get_info())
    print(is_torch_available())
    print(tensor_example())

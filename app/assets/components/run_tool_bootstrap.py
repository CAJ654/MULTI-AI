# Generic entry point for a ComponentKind.tool component's one-shot
# invocations (yt-dlp today; any future one-shot tool component reuses this
# rather than getting its own bootstrap script). Contrast
# searxng_bootstrap.py, which is specific to one long-running server.
#
# Same MULTI_AI_COMPONENT_PATH path-extension trick as the other bootstrap
# scripts here (see their doc comments for why it's needed at all). Then runs
# a named module the way `python -m <module> args...` would, via runpy, with
# sys.argv rebuilt from this script's own remaining arguments so the target
# module sees the args a real `-m` invocation would give it.
#
# Usage: python run_tool_bootstrap.py <module_name> [module args...]

import os
import runpy
import sys


def _extend_path() -> None:
    raw = os.environ.get("MULTI_AI_COMPONENT_PATH", "")
    for entry in reversed([p for p in raw.split(os.pathsep) if p]):
        if entry not in sys.path:
            sys.path.insert(0, entry)


def main() -> int:
    _extend_path()
    if len(sys.argv) < 2:
        print("usage: run_tool_bootstrap.py <module_name> [args...]", file=sys.stderr)
        return 2
    module = sys.argv[1]
    sys.argv = [module] + sys.argv[2:]
    runpy.run_module(module, run_name="__main__")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# Entry point for the bundled SearXNG component under the packaged Windows
# build's embeddable Python interpreter.
#
# Mirrors installer/runtime/bootstrap.py's _extend_path trick exactly, for the
# same reason: the embeddable interpreter's python._pth ignores PYTHONPATH, so
# the directory searxng_install.py put SearXNG and its dependencies into (this
# component's own isolated site-packages — see ComponentRuntime, deliberately
# never the main backend's) has to be added to sys.path in ordinary Python,
# after startup, rather than through an environment variable the interpreter
# would otherwise honor.
#
# SEARXNG_SETTINGS_PATH points SearXNG at the settings.yml this app generated
# (see searxng_settings.yml.tmpl) instead of its own packaged default.

import os
import sys


def _extend_path() -> None:
    raw = os.environ.get("MULTI_AI_COMPONENT_PATH", "")
    for entry in reversed([p for p in raw.split(os.pathsep) if p]):
        if entry not in sys.path:
            sys.path.insert(0, entry)


def _trust_system_certs() -> None:
    """SearXNG's engines talk to search providers over httpx, which verifies
    against certifi's bundled CA list -- so on a machine whose antivirus or
    proxy intercepts TLS, every engine fails with CERTIFICATE_VERIFY_FAILED and
    searches come back empty. truststore (installed by searxng_install.py)
    routes verification through the OS certificate store instead, the same
    outcome pip-system-certs gives the main backend."""
    try:
        import truststore

        truststore.inject_into_ssl()
    except Exception:
        # Older install without truststore, or an inject failure: fall back to
        # certifi rather than refusing to start.
        pass


def main() -> int:
    _extend_path()
    _trust_system_certs()

    settings_path = os.environ.get("SEARXNG_SETTINGS_PATH")
    if settings_path:
        # searx.settings_loader picks this up via SEARXNG_SETTINGS_PATH; set
        # explicitly (rather than relying on the caller's env) so this script
        # never accidentally boots against SearXNG's own packaged default.
        os.environ["SEARXNG_SETTINGS_PATH"] = settings_path

    # Imported only after the path is built — searx lives in this component's
    # site-packages, not anywhere the interpreter finds on its own.
    from searx.webapp import run

    run()
    return 0


if __name__ == "__main__":
    sys.exit(main())

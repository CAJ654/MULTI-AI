# Installs the bundled SearXNG component under the packaged Windows build's
# *embeddable* Python interpreter.
#
# Why this isn't just `pip install <archive>`: SearXNG ships as an sdist (a
# setup.py, no pyproject.toml, no wheel). Building an sdist runs PEP 517 build
# isolation, which installs setuptools into a scratch environment and exposes
# it via PYTHONPATH -- and the embeddable interpreter's python._pth makes it
# ignore PYTHONPATH (the same trap installer/runtime/bootstrap.py documents).
# The build backend subprocess then dies with "Cannot import
# 'setuptools.build_meta'" and pip exits 2. There is no supported way around
# that from inside the embeddable interpreter.
#
# So the install happens in two halves, neither of which builds anything:
#   1. pip installs SearXNG's pinned dependencies (all wheels) plus tzdata and
#      truststore -- see searxng_requirements.txt for why those two.
#   2. the `searx/` package is copied straight out of the GitHub archive (it is
#      pure Python), a version_frozen.py is written so it never shells out to
#      git at runtime, and valkeydb.py's POSIX-only `import pwd` is guarded
#      (SearXNG upstream has declined to support Windows, so this is on us).
#
# Usage:
#   python searxng_install.py --target <site-packages> \
#       --requirements <searxng_requirements.txt> --pip <pip.pyz>
#
# stdout/stderr stream straight through to the Add-ons install screen, so the
# progress lines here are deliberately plain and single-line.

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

_ARCHIVE_PREFIX = "# archive:"


def _log(msg: str) -> None:
    print(msg, flush=True)


def _archive_url(requirements_path: str) -> str:
    """The pinned SearXNG source archive, read from the `# archive:` line in
    searxng_requirements.txt -- kept there so a version bump touches one file."""
    with open(requirements_path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith(_ARCHIVE_PREFIX):
                return stripped[len(_ARCHIVE_PREFIX):].strip()
    raise SystemExit(
        f"no '{_ARCHIVE_PREFIX} <url>' line in {requirements_path}"
    )


def _pip_install(pip_pyz: str, target: str, requirements_path: str) -> None:
    """Install the wheel dependencies. Plain wheels only -- no sdist, so none of
    the build-isolation machinery that the embeddable interpreter breaks."""
    _log("Installing dependencies...")
    result = subprocess.run(
        [
            sys.executable,
            pip_pyz,
            "install",
            "--target", target,
            "--requirement", requirements_path,
            # See BackendRuntime.provision()'s note on the same flag: without it
            # a re-run after a version bump keeps the old packages and still
            # reports success.
            "--upgrade",
            "--no-warn-script-location",
            "--progress-bar", "off",
        ],
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"dependency install failed (pip exited {result.returncode})"
        )


def _download(url: str, dest_dir: str) -> str:
    """Fetch the archive over TLS that trusts the OS certificate store, so this
    works behind the same TLS-intercepting antivirus/proxies that
    pip-system-certs handles for the main backend. truststore was just
    installed into `target`, which is on sys.path by the time this runs."""
    import truststore  # noqa: E402  (only importable after _pip_install)

    truststore.inject_into_ssl()
    _log("Downloading SearXNG...")
    archive_path = os.path.join(dest_dir, "searxng.zip")
    try:
        with urllib.request.urlopen(url, timeout=60) as response:  # nosec B310 (pinned https URL)
            data = response.read()
    except OSError as exc:  # URLError, timeouts, connection resets
        raise SystemExit(f"could not download SearXNG ({exc})")
    with open(archive_path, "wb") as handle:
        handle.write(data)
    return archive_path


def _extract_searx_package(archive_path: str, target: str) -> None:
    """Copy just the `searx/` tree out of the archive into `target/searx`,
    replacing any previous copy so a downgrade doesn't leave stale modules."""
    with zipfile.ZipFile(archive_path) as archive:
        # GitHub archives nest everything under a single `<repo>-<sha>/` dir.
        root = archive.namelist()[0].split("/", 1)[0] + "/"
        searx_prefix = root + "searx/"

        dest_searx = os.path.join(target, "searx")
        if os.path.isdir(dest_searx):
            shutil.rmtree(dest_searx)

        count = 0
        for info in archive.infolist():
            if info.is_dir() or not info.filename.startswith(searx_prefix):
                continue
            relative = info.filename[len(root):]
            out_path = os.path.join(target, relative)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with archive.open(info) as source, open(out_path, "wb") as out:
                shutil.copyfileobj(source, out)
            count += 1
    if count == 0:
        raise SystemExit("archive contained no searx/ package - wrong URL?")
    _log(f"Unpacked {count} SearXNG files")


def _freeze_version(target: str, archive_url: str) -> None:
    """Write searx/version_frozen.py. searx.version imports this if present and
    otherwise shells out to `git` on every startup -- which, in an unpacked
    archive with no .git, just logs errors and falls back to 1.0.0 anyway."""
    short = archive_url.rsplit("/", 1)[-1].removesuffix(".zip")[:10]
    version = f"1.0.0+{short}"
    body = (
        "# SPDX-License-Identifier: AGPL-3.0-or-later\n"
        "# Written by searxng_install.py so searx.version never calls git.\n"
        f'VERSION_STRING = "{version}"\n'
        f'VERSION_TAG = "{version}"\n'
        f'DOCKER_TAG = "{version.replace("+", "-")}"\n'
        'GIT_URL = "https://github.com/searxng/searxng"\n'
        'GIT_BRANCH = "master"\n'
    )
    with open(os.path.join(target, "searx", "version_frozen.py"), "w", encoding="utf-8") as handle:
        handle.write(body)


def _guard_pwd_import(target: str) -> None:
    """searx/valkeydb.py does a bare `import pwd` (POSIX-only) at module scope,
    and searx.webapp imports it unconditionally, so on Windows every startup
    dies with ModuleNotFoundError before Flask even loads. The name is only
    used inside one error path that this local, limiter-off deployment never
    reaches. Upstream has declined a fix (searxng/searxng#5412), so patch it
    here: turn the import into a guarded one."""
    path = os.path.join(target, "searx", "valkeydb.py")
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    original = "\nimport pwd\n"
    if original not in source:
        # Already patched, or upstream restructured the import -- either way,
        # don't guess.
        return
    guarded = (
        "\ntry:\n"
        "    import pwd\n"
        "except ImportError:  # POSIX-only; absent on Windows (searxng/searxng#5412)\n"
        "    pwd = None\n"
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source.replace(original, guarded, 1))


def main() -> int:
    # The Add-ons install screen decodes this pipe as UTF-8; without this the
    # embeddable interpreter writes it in the Windows ANSI codepage.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except (AttributeError, ValueError):
        pass

    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--requirements", required=True)
    parser.add_argument("--pip", required=True)
    args = parser.parse_args()

    os.makedirs(args.target, exist_ok=True)
    url = _archive_url(args.requirements)

    _pip_install(args.pip, args.target, args.requirements)

    if args.target not in sys.path:
        sys.path.insert(0, args.target)

    with tempfile.TemporaryDirectory() as scratch:
        archive_path = _download(url, scratch)
        _extract_searx_package(archive_path, args.target)

    _freeze_version(args.target, url)
    _guard_pwd_import(args.target)

    _log("Web search installed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Shared bits for the tools/ scripts: repo root, pinned versions, checked downloads, Godot.

Stdlib only, so every script runs with a bare Python 3.12+ on Windows and Linux.
"""

import hashlib
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
VERSION = (ROOT / ".godot-version").read_text().strip()
SUMS = ROOT / "tools" / f"godot-{VERSION}.sha512"
RELEASES = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable"


def log(*args):
    """Logs go to stderr, so stdout stays free for printed paths."""
    print(*args, file=sys.stderr, flush=True)


def fail(message):
    log(message)
    sys.exit(1)


def run(*cmd, **kwargs):
    """Runs a command and exits with its code if it fails."""
    code = subprocess.run([str(c) for c in cmd], check=False, **kwargs).returncode
    if code:
        fail(f"{Path(str(cmd[0])).name} {' '.join(map(str, cmd[1:]))} failed (exit {code})")


def expected_sum(name):
    """The sha512 of a Godot release file, from tools/godot-<version>.sha512."""
    if not SUMS.exists():
        fail(f"Missing {SUMS}. Add the SHA512 lines for Godot {VERSION} from its release's SHA512-SUMS.txt.")
    for line in SUMS.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == name:
            return parts[0].lower()
    fail(f"No checksum for {name} in {SUMS}. Add its line from the release's SHA512-SUMS.txt.")


def download(url, dest, algorithm, expected):
    """Downloads url to dest and fails unless its hash matches."""
    urllib.request.urlretrieve(url, dest)
    digest = hashlib.new(algorithm)
    with open(dest, "rb") as f:
        while chunk := f.read(1 << 20):
            digest.update(chunk)
    if digest.hexdigest() != expected.lower():
        fail(f"Checksum mismatch for {Path(dest).name}")


def godot():
    """Path of the Godot binary: $GODOT_BIN, or the pinned one (installed on first use)."""
    import install  # here, not at the top: install imports this module

    return os.environ.get("GODOT_BIN") or str(install.godot())


def godot_import(godot_bin, path=GAME):
    """Imports the project once, so class_name scripts and resources are registered."""
    subprocess.run(
        [godot_bin, "--headless", "--import", "--path", str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

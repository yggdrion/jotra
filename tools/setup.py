"""One-time setup of a dev machine; safe to re-run. Installs the pinned Python packages
(gdtoolkit, pre-commit), the pinned Godot, webrtc-native, gdUnit4 and Bun (lobby), the pre-push hook, then runs the
quick check.

Needs: Python 3.12+ and git on PATH.
Not installed here: export templates (export.py fetches them on first use).
"""

import sys

import install
from _common import ROOT, run

py = sys.executable

print("== Python packages", flush=True)
run(py, "-m", "pip", "install", "--disable-pip-version-check", "-r", "tools/requirements.txt", cwd=ROOT)
print("\n== Godot", flush=True)
install.godot()
print("\n== webrtc-native", flush=True)
install.webrtc()
print("\n== gdUnit4", flush=True)
install.gdunit4()
print("\n== Bun", flush=True)
install.bun()
print("\n== Git hooks", flush=True)
run(py, "-m", "pre_commit", "install", "-f", "--hook-type", "pre-push", cwd=ROOT)
run(py, "tools/check.py", "--quick", cwd=ROOT)
print("\nSetup done. Run python tools/check.py for the full check.")

"""Exports a release build with the pinned Godot version and export templates.

Usage: python tools/export.py <linux|windows|macos> [output dir, default build/<platform>]
"""

import subprocess
import sys
from pathlib import Path

import install
from _common import GAME, ROOT, fail, godot, godot_import, run

PRESETS = {
    "linux": ("Linux", "jotra.x86_64"),
    "windows": ("Windows Desktop", "jotra.exe"),
    # A universal (x86_64 + arm64) app bundle, ad-hoc signed, zipped by Godot.
    # Its Info.plist sets NSAppSleepDisabled (preset option additional_plist_content): the solo
    # and host server is a windowless child process, and App Nap throttled it to a tick every
    # few seconds.
    "macos": ("macOS", "jotra.zip"),
}

if len(sys.argv) not in (2, 3) or sys.argv[1] not in PRESETS:
    fail("Usage: python tools/export.py <linux|windows|macos> [output dir]")
preset, file = PRESETS[sys.argv[1]]
out = Path(sys.argv[2] if len(sys.argv) == 3 else ROOT / "build" / sys.argv[1]).resolve()

godot_bin = godot()
install.templates()
out.mkdir(parents=True, exist_ok=True)
godot_import(godot_bin)
# The commit goes into the pck so a build can tell which commit it is; runs from source have
# no file and count as "dev".
# A fixed slice of the full hash: `--short` picks its length from the clone's object count, so
# a shallow CI clone and a full local clone could disagree on the same commit.
try:
    git = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=ROOT, check=False
    )
    commit = git.stdout.strip()[:12] if git.returncode == 0 else ""
except OSError:  # no git on PATH
    commit = ""
build_id = GAME / "build_id.txt"
build_id.write_text(commit or "dev")
try:
    run(godot_bin, "--headless", "--export-release", preset, out / file, cwd=GAME)
finally:
    build_id.unlink()
# Godot can exit 0 after a failed export, so check the result.
if not (out / file).exists() or (out / file).stat().st_size == 0:
    fail(f"Export of {preset} produced no {out / file}")
print(f"Exported {preset} to {out / file}")

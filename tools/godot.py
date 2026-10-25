"""Runs the pinned Godot version, installing it first if needed.

Example: python tools/godot.py --path game -e
"""

import subprocess
import sys

from _common import godot, godot_import

args = sys.argv[1:]
godot_bin = godot()
# Running the game skips the class_name scan the editor does, so a checkout that pulled new
# scripts would fail with "Could not find type". Import first; it is quick when up to date.
# Only --path: other args (--quit-after, game args) could cut the import short.
if not {"-e", "--editor", "--import"} & set(args):
    i = args.index("--path") if "--path" in args else -1
    godot_import(godot_bin, args[i + 1] if 0 <= i < len(args) - 1 else ".")
sys.exit(subprocess.run([godot_bin, *args], check=False).returncode)

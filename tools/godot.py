"""Runs the pinned Godot version, installing it first if needed. Without --path it runs the
project in game/, from any working directory.

Example: python tools/godot.py -e
"""

import subprocess
import sys

from _common import GAME, godot, godot_import

args = sys.argv[1:]
if "--path" not in args:
    args = ["--path", str(GAME), *args]
godot_bin = godot()
# Running the game skips the class_name scan the editor does, so a checkout that pulled new
# scripts would fail with "Could not find type". Import first; it is quick when up to date.
# Only --path: other args (--quit-after, game args) could cut the import short.
if not {"-e", "--editor", "--import"} & set(args):
    i = args.index("--path")
    godot_import(godot_bin, args[i + 1] if i < len(args) - 1 else GAME)
sys.exit(subprocess.run([godot_bin, *args], check=False).returncode)

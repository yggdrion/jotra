"""Runs all gdUnit4 tests headless with the pinned Godot version.

Extra arguments go to gdUnit4, e.g. python tools/run_tests.py -a res://tests/tower_test.gd
Set GODOT_BIN to use your own binary; it must match .godot-version.
"""

import subprocess
import sys

import install
from _common import GAME, VERSION, fail, godot, godot_import

godot_bin = godot()
out = subprocess.run([godot_bin, "--headless", "--version"], capture_output=True, text=True, check=False)
actual = (out.stdout.strip().splitlines() or [""])[-1].strip()
if not actual.startswith(f"{VERSION}.stable."):
    fail(f"GODOT_BIN is Godot {actual}, but .godot-version pins {VERSION}")

install.gdunit4()
godot_import(godot_bin)
test_args = ["--headless", "--ignoreHeadlessMode", "-a", "res://tests", *sys.argv[1:]]
# What the addon's runtest.sh/.cmd do. The unreachable remote debugger keeps Godot from
# dropping into its interactive debugger on script errors.
code = subprocess.run(
    [godot_bin, "--path", ".", "-s", "-d", "--remote-debug", "tcp://127.0.0.1:0",
     "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", *test_args],
    cwd=GAME,
    check=False,
).returncode
print(f"Run tests ends with {code}", flush=True)
subprocess.run(
    [godot_bin, "--headless", "--path", ".", "--quiet", "-s",
     "res://addons/gdUnit4/bin/GdUnitCopyLog.gd", *test_args],
    cwd=GAME,
    stdout=subprocess.DEVNULL,
    check=False,
)
sys.exit(code)

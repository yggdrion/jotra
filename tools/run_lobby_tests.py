"""Runs the lobby's tests (lobby/, bun test) with the pinned Bun.

Usage: python tools/run_lobby_tests.py [bun test args]
Set BUN_BIN to use your own binary.
"""

import sys

from _common import ROOT, bun, run

run(bun(), "test", *sys.argv[1:], cwd=ROOT / "lobby")

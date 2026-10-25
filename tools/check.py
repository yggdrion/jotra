"""Runs the same checks as CI locally, in CI order, and stops at the first failure:
  1. gdlint + gdformat --check   2. gdUnit4 tests (pinned Godot)   3. headless network test

Usage: python tools/check.py [--quick] [--export]
  --quick   only step 1 (no Godot), a few seconds
  --export  also export the Linux and Windows builds to build/<platform>/
Needs: python tools/setup.py once (Python packages, Godot, gdUnit4, hooks). setup.py also
installs it as a git pre-push hook (skip once with: git push --no-verify).
"""

import importlib.util
import sys

from _common import ROOT, fail, run

args = set(sys.argv[1:])
if not args <= {"--quick", "--export"}:
    fail("Usage: python tools/check.py [--quick] [--export]")
py = sys.executable
dirs = ["game/scripts", "game/tests"]


def step(name):
    print(f"\n== {name}", flush=True)


def tool(name, *tool_args):
    run(py, f"tools/{name}.py", *tool_args, cwd=ROOT)


step("Lint and format")
# Through python -m, so a user-site pip install works without its Scripts dir on PATH.
if not importlib.util.find_spec("gdtoolkit"):
    fail("gdtoolkit not installed: run python tools/setup.py")
run(py, "-m", "gdtoolkit.linter", *dirs, cwd=ROOT)
run(py, "-m", "gdtoolkit.formatter", "--check", *dirs, cwd=ROOT)

if "--quick" in args:
    print("\nQuick checks passed (Godot tests skipped).")
    sys.exit(0)

step("gdUnit4 tests")
tool("run_tests")

step("Network test")
tool("run_network_test")

if "--export" in args:
    step("Export")
    tool("export", "linux")
    tool("export", "windows")

print("\nAll checks passed.")

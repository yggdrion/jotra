# Jotra

Norse dark-fantasy co-op survival game (Godot 4.7.2, GDScript). Scope, design and
architecture: [docs/PLAN.md](docs/PLAN.md).

## Setup

Needs Python 3.12+ and git. Safe to re-run:

    python tools/setup.py

Installs gdtoolkit and pre-commit, the pinned Godot (`.godot-version`, checked against
`tools/godot-<version>.sha512`, into `.tools/`), gdUnit4 and the pre-push hook.

## Run

    python tools/godot.py --path game        # solo: spawns a local headless server and joins it
    python tools/godot.py --path game -e     # editor
    python tools/dev.py 3                    # headless server + 3 windowed clients on localhost

Move with WASD. The game starts fullscreen; F11 or Alt+Enter toggles a window (or start with
`-- --windowed`). F3 toggles the debug overlay (fps, build, server, ping, snapshot rate,
player count, position); release builds have it too. Command line roles (after `--`): `--server --port=N [--solo]`,
`--connect=host:port`, `--bot --expect=N` (headless test client).

## Check

    python tools/check.py            # lint, format, gdUnit4 tests, network test (also the pre-push hook)
    python tools/check.py --quick    # lint + format only
    python tools/run_tests.py -a res://tests/sim_world_test.gd
    python tools/run_network_test.py # headless server + bots over ENet
    python tools/export.py windows   # release build to build/windows/

CI runs the same scripts on every push and uploads Linux and Windows builds as artifacts.

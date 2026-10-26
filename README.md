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

Move with WASD, E removes the nearest tree or rock. Left mouse is a light attack, right mouse a
heavy one (both toward the mouse), Space dashes through hits; attacks and dashes cost stamina.
Enemies (red; orange while winding up a hit) spawn around players, more and tougher when players
stand together. On death you respawn at the world spawn after 3 s. The game starts fullscreen; F11 or Alt+Enter toggles a window (or start with
`-- --windowed`). F3 toggles the debug overlay (fps, build, server, ping, snapshot rate,
player count, position, world seed, chunk); release builds have it too. Command line roles (after `--`):
`--server --port=N [--solo] [--world=DIR] [--metrics-port=N]`, `--connect=host:port [--name=NAME]`,
`--bot --expect=N` (headless test client).

Worlds are saved in `user://worlds/` (`default` for servers, `solo` for solo games; on Windows
`%APPDATA%/Godot/app_userdata/Jotra/`), every 60 s, when the last player leaves and on
shutdown. Players are known by name: `--name`, or a random one kept in `user://player.txt`.

## Dedicated server

A local Docker image (`deploy/Dockerfile`) built from the Linux export:

    python tools/export.py linux
    docker compose -f deploy/docker-compose.yml up -d --build

Players join with `jotra -- --connect=<host>:17777`. The server pauses its world while nobody
is online. The world lives in the `world` volume (`/data/world`), so it survives rebuilds;
`docker compose stop` has the server save before it exits.
Prometheus metrics (`jotra_*`: players, enemies, tick time, bandwidth, loaded chunks, save time, build) are on
`127.0.0.1:9310/metrics`; a Grafana dashboard for them is `deploy/grafana/jotra.json`.
Deploying to the vServer is the last milestone (`docs/PLAN.md` §8).

## Check

    python tools/check.py            # lint, format, gdUnit4 tests, network test (also the pre-push hook)
    python tools/check.py --quick    # lint + format only
    python tools/run_tests.py -a res://tests/sim_world_test.gd
    python tools/run_network_test.py # headless server + bots over ENet
    python tools/export.py windows   # release build to build/windows/

CI runs the same scripts on every push and uploads Linux and Windows builds as artifacts.

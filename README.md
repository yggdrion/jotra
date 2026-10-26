# Jotra

Norse dark-fantasy co-op survival game (Godot 4.7.2, GDScript). Scope, design and
architecture: [docs/PLAN.md](docs/PLAN.md).

## Setup

Needs Python 3.12+ and git. Safe to re-run:

    python tools/setup.py

Installs gdtoolkit and pre-commit, the pinned Godot (`.godot-version`, checked against
`tools/godot-<version>.sha512`, into `.tools/`), the webrtc-native GDExtension, gdUnit4, the
pinned Bun (for the lobby) and the pre-push hook.

## Run

    python tools/godot.py --path game        # start menu: play solo, host a game, join by code
    python tools/godot.py --path game -e     # editor
    python tools/dev.py 3                    # headless server + 3 windowed clients on localhost

The start menu offers three ways in. **Play solo** spawns a local headless server and joins it.
**Host a game** spawns the same server on the same world, which opens a room in the lobby; its
four-letter code shows in the top-right corner, and friends type it under **Join** to play in
your world over WebRTC from their own networks (through a TURN relay when a direct connection
fails). Friends can join and leave any time; the game ends for everyone when the host leaves.
If a game can't be reached or ends, you are back in the menu with the reason.

**Not live yet:** the built-in lobby (`wss://jotra.r4b2.de/ws`) is deployed with milestone M9a.
Until then Host and Join only work through a lobby you run yourself, started from the command
line with `--lobby=URL` (see [Lobby](#lobby-player-host) below); solo is unaffected.

Move with WASD, E removes the nearest tree or rock. Left mouse is a light attack, right mouse a
heavy one (both toward the mouse), Space dashes through hits; attacks and dashes cost stamina.
Enemies (red; orange while winding up a hit) spawn around players, more and tougher when players
stand together. On death you respawn at the world spawn after 3 s. E fells the outlined tree
or breaks the outlined rock in reach (a prompt at the bottom says which). Trees, rocks and slain
enemies drop items, which slide to you when you walk near. Tab or I opens the inventory: drag
items to move, stack, wear or take them off, right click to wear or take off at once, and point
at anything for what it is, where it comes from and what it makes. Recipes show what you have
against what they need and why one can't be made yet; most need the labeled workbench at the
spawn. The mouse doesn't swing while the inventory is open. Hunger (the brown bar) drains over
time: while it is above zero you slowly heal, at zero you lose health and stamina comes back
slower. Trees drop berries; F or a right click in the inventory eats. Days last 8 minutes and
nights 4; at night the world darkens and more, tougher enemies spawn. E at the Barrow left of the
spawn enters a dungeon run (anyone entering within 30 s joins the same one): a chain of rooms
whose draugr wake as you walk in, tougher the deeper you go and the longer you take. Slain ones
may drop buff orbs (listed top left, some pairs combine into a synergy); clearing the rooms
heals you. Clear the end chamber to open its chest, then E at the way out to keep everything.
Die inside, or quit, and you are back at the Barrow with what you carried in and no buffs. The
game starts fullscreen; F11 or Alt+Enter toggles a window (or start with
`-- --windowed`). F3 toggles the debug overlay (fps, build, server, ping, snapshot rate,
player count, position, world seed, chunk; in a room also the ICE candidates the host offered);
release builds have it too. Command line roles (after `--`, all in `game/scripts/boot/main.gd`):
`--server --port=N [--solo] [--world=DIR] [--metrics-port=N]`, `--server --lobby=URL
[--room-file=PATH] [--owner=NAME]` (a server in a lobby room), `--connect=host:port`,
`--join=CODE`, `--host`, `--lobby=URL` (default `wss://jotra.r4b2.de/ws`), `--name=NAME`,
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
Prometheus metrics (`jotra_*`: players, enemies, drops, tick time, bandwidth, loaded chunks, save time, build) are on
`127.0.0.1:9310/metrics`; a Grafana dashboard for them is `deploy/grafana/jotra.json`.
Deploying to the vServer is the last milestone (`docs/PLAN.md` §8).

## Lobby (player host)

`lobby/` is the Bun lobby that hands out room codes and relays WebRTC signaling; it never sees
gameplay. Locally:

    .tools/bun/1.4.4/bun lobby/src/server.ts                       # PORT=8080 by default
    python tools/godot.py --path game -- --host --lobby=ws://127.0.0.1:8080/ws

Friends on the same network join with `-- --join=CODE --lobby=ws://<host's ip>:8080/ws`.

Its deployment with coturn (STUN + TURN) is `deploy/lobby/` (see its README).

## Check

    python tools/check.py            # lint, format, lobby tests, gdUnit4 tests, network test (also the pre-push hook)
    python tools/check.py --quick    # lint + format only
    python tools/run_tests.py -a res://tests/sim_world_test.gd
    python tools/run_lobby_tests.py  # bun test in lobby/
    python tools/run_network_test.py # headless server + bots over ENet, then over WebRTC via a local lobby
    python tools/export.py windows   # release build to build/windows/
    python tools/balance_sim.py --quick --players 1   # bots play the sim headless: deaths, damage, gear times
    python tools/balance_sim.py --dungeon --quick     # bots take dungeon runs: clears, deaths, depth, buffs

CI runs the same scripts on every push and uploads Linux and Windows builds as artifacts.

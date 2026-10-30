"""Headless network test on localhost, over ENet and over WebRTC through a local lobby:

  1. One server and BOTS bot clients. Each bot walks in a circle and exits 0 once the server
     echoes its position, it has chunks and an enemy and it has seen every other bot moving (GameClient bot
     mode). The server's metrics endpoint must then show the ticks that ran, and the world dir
     the bots' saved positions.
  2. A --solo server and one bot: the server must exit on its own once the bot leaves, as it
     does when the solo player closes the game.
  3. A bot without --connect, which spawns its own solo server like the game does.
  4. A local lobby (lobby/, pinned Bun), a server that opens a room in it and BOTS bots that
     join by the room code over WebRTC, with the same checks as run 1.
  5. A --host bot, which spawns its own host server, reads the room code and joins it over
     WebRTC like the game's "Host a game"; the server must exit once the bot leaves.

Usage: python tools/run_network_test.py
Set GODOT_BIN to use your own binary; it must match .godot-version.
"""

import os
import re
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

from _common import GAME, ROOT, bun, fail, godot, godot_import

BOTS = 2
PORT = 17790
TIMEOUT = 60
LOBBY_PORT = 17795

godot_bin = godot()
godot_import(godot_bin)
logs = Path(tempfile.mkdtemp(prefix="jotra-net-"))


def start(name, *args):
    out = open(logs / f"{name}.log", "wb")  # noqa: SIM115, closed with the process
    return subprocess.Popen(
        [godot_bin, "--headless", "--path", ".", "--", *args],
        cwd=GAME,
        stdout=out,
        stderr=subprocess.STDOUT,
    )


def metric(port, name):
    text = urllib.request.urlopen(f"http://127.0.0.1:{port}/metrics", timeout=5).read().decode()
    return next((line.split()[1] for line in text.splitlines() if line.startswith(f"{name} ")), "0"), text


def wait_for(what, check, timeout=TIMEOUT):
    """Polls check() until it returns something truthy, which is returned."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if result := check():
                return result
        except OSError:
            pass
        time.sleep(0.2)
    dump()
    fail(f"timed out waiting for {what}")


def dump():
    for log in sorted(logs.glob("*.log")):
        print(f"--- {log.name}")
        print(log.read_text(errors="replace"))


procs = []


def wait(proc, what):
    try:
        code = proc.wait(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        dump()
        fail(f"{what} did not finish within {TIMEOUT}s")
    if code:
        dump()
        fail(f"{what} exited with {code}")


try:
    world = logs / "world"
    procs.append(start("server", "--server", f"--port={PORT}", f"--metrics-port={PORT}", f"--world={world}"))
    bots = [
        start(f"bot{i}", f"--connect=127.0.0.1:{PORT}", "--bot", f"--expect={BOTS - 1}", f"--name=bot{i}")
        for i in range(BOTS)
    ]
    procs += bots
    for i, bot in enumerate(bots):
        wait(bot, f"bot{i}")
    # ENet is UDP, so the metrics endpoint can share the port number over TCP.
    ticks, metrics = metric(PORT, "jotra_ticks_total")
    if int(ticks) == 0:
        dump()
        fail(f"metrics show no ticks:\n{metrics}")
    missing = [i for i in range(BOTS) if not (world / "players" / f"bot{i}.json").exists()]
    if missing:
        dump()
        fail(f"no saved player for bot(s) {missing} in {world}")
    procs.append(solo := start("solo", "--server", "--solo", f"--port={PORT + 1}", f"--world={logs / 'solo'}"))
    procs.append(bot := start("solo-bot", f"--connect=127.0.0.1:{PORT + 1}", "--bot", "--name=solo"))
    wait(bot, "solo bot")
    wait(solo, "solo server")
    procs.append(spawner := start("spawn-bot", "--bot"))
    wait(spawner, "bot with its own solo server")

    lobby_url = f"ws://127.0.0.1:{LOBBY_PORT}/ws"
    out = open(logs / "lobby.log", "wb")  # noqa: SIM115, closed with the process
    procs.append(
        subprocess.Popen(
            [bun(), str(ROOT / "lobby" / "src" / "server.ts")],
            env={**os.environ, "PORT": str(LOBBY_PORT)},
            stdout=out,
            stderr=subprocess.STDOUT,
        )
    )
    wait_for("the lobby", lambda: urllib.request.urlopen(f"http://127.0.0.1:{LOBBY_PORT}/healthz", timeout=1))
    room_file = logs / "room.txt"
    procs.append(
        start(
            "room-server",
            "--server",
            f"--lobby={lobby_url}",
            f"--room-file={room_file}",
            f"--metrics-port={PORT + 2}",
            f"--world={logs / 'room'}",
        )
    )
    code = wait_for("a room code", lambda: room_file.exists() and room_file.read_text().strip())
    if not re.fullmatch("[A-HJKMNP-Z]{8}", code):
        dump()
        fail(f"the server could not open a room: {code}")
    rtc_bots = [
        start(f"rtc-bot{i}", f"--lobby={lobby_url}", f"--join={code}", "--bot", f"--expect={BOTS - 1}", f"--name=rtc{i}")
        for i in range(BOTS)
    ]
    procs += rtc_bots
    for i, bot in enumerate(rtc_bots):
        wait(bot, f"WebRTC bot{i}")
    _, metrics = metric(PORT + 2, "jotra_ticks_total")
    if 'transport="webrtc"' not in metrics:
        dump()
        fail(f"room server metrics do not say webrtc:\n{metrics}")
    procs.append(host := start("host-bot", f"--lobby={lobby_url}", "--host", "--bot", "--name=host"))
    wait(host, "bot hosting its own server")
    # The spawned host server is not ours to wait on; the lobby sees its room close.
    wait_for(
        "the host server to close its room",
        lambda: metric(LOBBY_PORT, "jotra_lobby_rooms")[0] == "1",
    )
finally:
    for p in procs:
        p.kill()
print(
    f"Network test passed: {BOTS} bots saw each other and enemies and got chunks over ENet and over WebRTC, "
    "metrics served, players saved, solo and host servers exited with their player, solo and host spawn work."
)

"""Headless network test over ENet on localhost, in two runs:

  1. One server and BOTS bot clients. Each bot walks in a circle and exits 0 once the server
     echoes its position and it has seen every other bot moving (GameClient bot mode).
  2. A --solo server and one bot: the server must exit on its own once the bot leaves, as it
     does when the solo player closes the game.
  3. A bot without --connect, which spawns its own solo server like the game does.

Usage: python tools/run_network_test.py
Set GODOT_BIN to use your own binary; it must match .godot-version.
"""

import subprocess
import tempfile
from pathlib import Path

from _common import GAME, fail, godot, godot_import

BOTS = 2
PORT = 17790
TIMEOUT = 60

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
    procs.append(start("server", "--server", f"--port={PORT}"))
    bots = [start(f"bot{i}", f"--connect=127.0.0.1:{PORT}", "--bot", f"--expect={BOTS - 1}") for i in range(BOTS)]
    procs += bots
    for i, bot in enumerate(bots):
        wait(bot, f"bot{i}")
    procs.append(solo := start("solo", "--server", "--solo", f"--port={PORT + 1}"))
    procs.append(bot := start("solo-bot", f"--connect=127.0.0.1:{PORT + 1}", "--bot"))
    wait(bot, "solo bot")
    wait(solo, "solo server")
    procs.append(spawner := start("spawn-bot", "--bot"))
    wait(spawner, "bot with its own solo server")
finally:
    for p in procs:
        p.kill()
print(f"Network test passed: {BOTS} bots saw each other, solo server exited with its player, solo spawn works.")

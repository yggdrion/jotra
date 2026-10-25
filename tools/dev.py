"""Dev launcher: one headless server plus N windowed clients joining it on localhost.

Usage: python tools/dev.py [clients, default 2]
Closing every client window (or Ctrl+C) stops the server too. For plain solo, run the game
without arguments instead: python tools/godot.py --path game
"""

import subprocess
import sys

from _common import GAME, fail, godot, godot_import

PORT = 17777

if len(sys.argv) > 2 or (len(sys.argv) == 2 and not sys.argv[1].isdigit()):
    fail("Usage: python tools/dev.py [clients]")
count = int(sys.argv[1]) if len(sys.argv) == 2 else 2
godot_bin = godot()
godot_import(godot_bin)


def start(*args):
    return subprocess.Popen([godot_bin, "--path", ".", *args], cwd=GAME)


server = start("--headless", "--", "--server", f"--port={PORT}")
clients = [start("--", f"--connect=127.0.0.1:{PORT}") for _ in range(count)]
try:
    for client in clients:
        client.wait()
except KeyboardInterrupt:
    pass
finally:
    for p in [server, *clients]:
        p.kill()

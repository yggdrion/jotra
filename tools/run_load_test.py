"""Load test (M9): BOTS headless bot clients roam for MINUTES against one dedicated server.

Each bot passes the network test's checks, then roams a wide circle on its own bearing and
swings every few seconds until its --duration is up. The server's metrics are scraped every
SCRAPE seconds into build/load/<time>.csv; at the end the run fails unless every bot exited 0,
no log has an error, all bots stayed online and tick time and bandwidth are within the budgets
in docs/PLAN.md §9.

Usage: python tools/run_load_test.py [--bots=10] [--minutes=30]
           [--target=HOST:PORT --metrics=URL]   against a running server (deploy/docker-compose.yml)
Not part of tools/check.py or CI: it takes the full run, and runner CPUs would skew tick times.
"""

import argparse
import csv
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

from _common import GAME, ROOT, fail, godot, godot_import

TICK_MEAN_MS = 5.0
TICK_MAX_MS = 1000 / 30
SENT_KBPS = 20.0  # per player, server to clients
RECEIVED_KBPS = 2.0  # per player, clients to server
RAMP = 30  # seconds for every bot to join and pass its checks; not measured
SCRAPE = 10
PORT = 17796
ERRORS = ("SCRIPT ERROR", "ERROR:")
COLUMNS = [
    "players",
    "loaded_chunks",
    "enemies",
    "drops",
    "ticks_total",
    "tick_seconds_total",
    "tick_seconds_max",
    "slow_ticks_total",
    "sent_bytes_total",
    "received_bytes_total",
]

parser = argparse.ArgumentParser()
parser.add_argument("--bots", type=int, default=10)
parser.add_argument("--minutes", type=float, default=30)
parser.add_argument("--target", help="HOST:PORT of a running server instead of a local one")
parser.add_argument("--metrics", help="its metrics URL, e.g. http://127.0.0.1:9310/metrics")
args = parser.parse_args()
if bool(args.target) != bool(args.metrics):
    fail("--target and --metrics go together")

godot_bin = godot()
godot_import(godot_bin)
logs = Path(tempfile.mkdtemp(prefix="jotra-load-"))
out_dir = ROOT / "build" / "load"
out_dir.mkdir(parents=True, exist_ok=True)
out = out_dir / f"{time.strftime('%Y%m%d-%H%M%S')}.csv"
target = args.target or f"127.0.0.1:{PORT}"
metrics_url = args.metrics or f"http://127.0.0.1:{PORT}/metrics"
duration = RAMP + args.minutes * 60


def start(name, *cmd):
    log = open(logs / f"{name}.log", "wb")  # noqa: SIM115, closed with the process
    return subprocess.Popen(
        [godot_bin, "--headless", "--path", ".", "--", *cmd], cwd=GAME, stdout=log, stderr=subprocess.STDOUT
    )


def scrape():
    text = urllib.request.urlopen(metrics_url, timeout=5).read().decode()
    values = dict(line.split()[:2] for line in text.splitlines() if line.startswith("jotra_") and "{" not in line)
    return {c: float(values.get(f"jotra_{c}", 0)) for c in COLUMNS}


procs = []
rows = []
try:
    if not args.target:
        procs.append(
            start("server", "--server", f"--port={PORT}", f"--metrics-port={PORT}", f"--world={logs / 'world'}")
        )
        time.sleep(3)
    bots = [
        start(
            f"bot{i}",
            f"--connect={target}",
            "--bot",
            f"--expect={args.bots - 1}",
            f"--duration={duration}",
            f"--name=load{i}",
        )
        for i in range(args.bots)
    ]
    procs += bots
    began = time.monotonic()
    with open(out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["seconds", *COLUMNS])
        while any(b.poll() is None for b in bots) and time.monotonic() - began < duration + 60:
            time.sleep(SCRAPE)
            try:
                row = {"seconds": time.monotonic() - began, **scrape()}
            except OSError as e:
                print(f"scrape failed: {e}")
                continue
            rows.append(row)
            writer.writerow([round(row["seconds"], 1), *(row[c] for c in COLUMNS)])
            f.flush()
            print(
                f"{row['seconds'] / 60:5.1f} min  {row['players']:.0f} players  {row['enemies']:.0f} enemies  "
                f"{row['loaded_chunks']:.0f} chunks  tick max {row['tick_seconds_max'] * 1000:.1f} ms",
                flush=True,
            )
    codes = [b.wait(timeout=60) for b in bots]
finally:
    for p in procs:
        p.kill()

problems = []
if bad := [i for i, c in enumerate(codes) if c]:
    problems.append(f"bots {bad} exited nonzero")
for log in sorted(logs.glob("*.log")):
    errors = [line for line in log.read_text(errors="replace").splitlines() if line.startswith(ERRORS)]
    if errors:
        problems.append(f"{log.name}: {len(errors)} error line(s), first: {errors[0]}")
measured = [r for r in rows if RAMP <= r["seconds"] <= duration]
if len(measured) < 2:
    fail(f"too few metrics scrapes after the ramp ({len(measured)}); logs in {logs}")
first, last = measured[0], measured[-1]
seconds = last["seconds"] - first["seconds"]
ticks = last["ticks_total"] - first["ticks_total"]
mean_ms = (last["tick_seconds_total"] - first["tick_seconds_total"]) / ticks * 1000 if ticks else 0
max_ms = last["tick_seconds_max"] * 1000
sent = (last["sent_bytes_total"] - first["sent_bytes_total"]) / seconds / args.bots / 1024
received = (last["received_bytes_total"] - first["received_bytes_total"]) / seconds / args.bots / 1024
fewest = min(r["players"] for r in measured)
if fewest < args.bots:
    problems.append(f"only {fewest:.0f} of {args.bots} players online at one point")
for name, value, budget, unit in [
    ("tick mean", mean_ms, TICK_MEAN_MS, "ms"),
    ("tick max", max_ms, TICK_MAX_MS, "ms"),
    ("sent per player", sent, SENT_KBPS, "KB/s"),
    ("received per player", received, RECEIVED_KBPS, "KB/s"),
]:
    print(f"{name:20} {value:8.2f} {unit:5} (budget {budget:.1f})")
    if value > budget:
        problems.append(f"{name} {value:.2f} {unit} over budget {budget:.1f}")
print(f"{'slow ticks':20} {last['slow_ticks_total']:8.0f} of {last['ticks_total']:.0f}")
print(f"{'peak enemies':20} {max(r['enemies'] for r in measured):8.0f}")
print(f"{'peak chunks':20} {max(r['loaded_chunks'] for r in measured):8.0f}")
print(f"metrics: {out}\nlogs: {logs}")
if problems:
    fail("Load test failed:\n  " + "\n  ".join(problems))
print(f"Load test passed: {args.bots} bots for {args.minutes:g} min within budget, no errors.")

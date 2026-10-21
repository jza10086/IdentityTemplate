#!/usr/bin/env python3
"""5- and 8-player real ENet Avalon games with independently addressed peers."""
from __future__ import annotations
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import sys
ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")

def run(count: int) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    children = {}
    streams = []
    with tempfile.TemporaryDirectory(prefix=f"avalon-enet-{count}-") as directory:
        output = Path(directory)
        try:
            for role in ["host"] + [f"client{i}" for i in range(1, count)]:
                log = (output / f"{role}.log").open("w", encoding="utf-8")
                streams.append(log)
                runtime = output / role
                runtime.mkdir()
                children[role] = subprocess.Popen(
                    [GODOT, "--headless", "--path", str(ROOT), "--script", "res://tests/test_avalon_network.gd", "--", role, str(port), directory, str(count)],
                    stdout=log, stderr=subprocess.STDOUT,
                    env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1", "XDG_DATA_HOME": str(runtime / "data"), "XDG_CACHE_HOME": str(runtime / "cache"), "XDG_CONFIG_HOME": str(runtime / "config")})
                time.sleep(0.25 if role == "host" else 0.08)
            deadline = time.monotonic() + 50
            while time.monotonic() < deadline:
                failed = [r for r, p in children.items() if p.poll() not in (None, 0)]
                if failed: raise RuntimeError("Failed processes: " + ", ".join(failed))
                if all(p.poll() is not None for p in children.values()): break
                time.sleep(0.05)
            else: raise RuntimeError("Timed out")
            for role in children:
                if not (output / f"{role}.passed").is_file(): raise RuntimeError("Missing success marker " + role)
                log = (output / f"{role}.log").read_text()
                if "SCRIPT ERROR:" in log or any(line.startswith("ERROR:") for line in log.splitlines()): raise RuntimeError("Runtime error in " + role)
            print(f"PASS: {count}-player real ENet Avalon; assassination and five-reject endings; per-peer role/ballot/quest secrecy; spoof and malformed payload resistance; rematch; disconnect abort.")
            return 0
        except Exception as error:
            print(f"FAIL ({count} players): {error}", file=sys.stderr)
            for role in children:
                print(f"\n--- {role} ---\n{(output / f'{role}.log').read_text()}", file=sys.stderr)
            return 1
        finally:
            for process in children.values():
                if process.poll() is None: process.terminate()
            for process in children.values():
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            for stream in streams: stream.close()

if __name__ == "__main__":
    if not GODOT: sys.exit("Set GODOT_BIN to a Godot 4 executable")
    sys.exit(run(5) or run(8))

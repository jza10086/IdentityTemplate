#!/usr/bin/env python3
"""Run real ENet match and eight-player lobby/admission smoke scenarios.

Usage: GODOT_BIN=/path/to/godot python3 tests/run_network_smoke.py
No mocks, shared SceneMultiplayer instances, or private-role RPCs are used.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
if not GODOT:
    bundled = ROOT.parent / "tools/godot47/Godot_v4.7.2-stable_linux.x86_64"
    if bundled.is_file():
        GODOT = str(bundled)
if not GODOT:
    sys.exit("Set GODOT_BIN to a Godot 4 executable.")


def run_scenario(scenario: str) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    children: dict[str, subprocess.Popen] = {}
    streams = []
    with tempfile.TemporaryDirectory(prefix="identity-party-enet-") as directory:
        output = Path(directory)

        def spawn(role: str) -> None:
            log = (output / f"{role}.log").open("w", encoding="utf-8")
            streams.append(log)
            runtime = output / role
            runtime.mkdir()
            children[role] = subprocess.Popen(
                [GODOT, "--headless", "--path", str(ROOT), "--script",
                 "res://tests/test_network.gd" if scenario == "match"
                 else "res://tests/test_network_admission.gd",
                 "--", role, str(port), directory],
                stdout=log, stderr=subprocess.STDOUT,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1",
                     "XDG_DATA_HOME": str(runtime / "data"),
                     "XDG_CONFIG_HOME": str(runtime / "config"),
                     "XDG_CACHE_HOME": str(runtime / "cache")},
            )

        try:
            spawn("host" if scenario == "match" else "capacityhost")
            time.sleep(0.35)
            for role in (("client1", "client2", "client3") if scenario == "match"
                         else ("duplicate", "invalid")):
                spawn(role)
                time.sleep(0.12)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if (output / "match_started").exists() and "late" not in children:
                    spawn("late")
                if scenario == "admission":
                    if ((output / "duplicate.passed").exists()
                            and (output / "invalid.passed").exists()
                            and "waiting1" not in children):
                        for index in range(1, 8):
                            spawn(f"waiting{index}")
                            time.sleep(0.08)
                    if (output / "room_full").exists() and "overflow" not in children:
                        spawn("overflow")
                failed = [role for role, process in children.items()
                          if process.poll() not in (None, 0)]
                if failed:
                    raise RuntimeError("Failed subprocesses: " + ", ".join(failed))
                if all(process.poll() is not None for process in children.values()):
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError("Network smoke test timed out")
            expected = ({"host", "client1", "client2", "client3", "late"}
                        if scenario == "match" else
                        {"capacityhost", "duplicate", "invalid", "overflow"}
                        | {f"waiting{index}" for index in range(1, 8)})
            if set(children) != expected:
                raise RuntimeError("Late-join subprocess was never launched")
            for role in expected:
                if not (output / f"{role}.passed").exists():
                    raise RuntimeError(f"Missing success marker for {role}")
                log_text = (output / f"{role}.log").read_text()
                if "SCRIPT ERROR:" in log_text or any(
                        line.startswith("ERROR:") for line in log_text.splitlines()):
                    raise RuntimeError(f"Unexpected Godot runtime error in {role}")
            if scenario == "match" and not (output / "late_rejected").exists():
                raise RuntimeError("Late-join rejection was not verified")
            if scenario == "match":
                print("PASS: 4-player real ENet match; private role views; sender spoof resistance; late join rejection; rematch; disconnect returns all peers to lobby.")
            else:
                print("PASS: 8-player real ENet lobby; ninth-player rejection; server-side duplicate/invalid name rejection; minimum player count and readiness gate; host disconnect.")
            return 0
        except Exception as error:
            print(f"FAIL: {error}", file=sys.stderr)
            for role in children:
                print(f"\n--- {role} ---\n{(output / f'{role}.log').read_text()}", file=sys.stderr)
            return 1
        finally:
            for process in children.values():
                if process.poll() is None:
                    process.terminate()
            for process in children.values():
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for stream in streams:
                stream.close()


if __name__ == "__main__":
    sys.exit(run_scenario("match") or run_scenario("admission"))

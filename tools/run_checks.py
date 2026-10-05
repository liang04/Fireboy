#!/usr/bin/env python3
"""Cross-platform Fireboy checks with isolated saves; no packages required."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUPPORTED_GODOT = ("4.6.3", "4.7")


def main():
    # Windows consoles may default to GBK, which cannot print Godot's check marks.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--skip-smoke", action="store_true", help="Skip the longer 10-level probe")
    parser.add_argument("--skip-routes", action="store_true", help="Skip full-gem input replays")
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error("Godot not found. Pass --godot /path/to/Godot (Windows: use _console.exe).")
    with tempfile.TemporaryDirectory(prefix="fireboy-checks-") as temporary:
        isolated = Path(temporary) / "Fireboy-optimization-tests"
        env = os.environ.copy()
        # Windows uses APPDATA; Linux uses XDG_DATA_HOME. HOME also isolates macOS.
        for key, leaf in [("HOME", "home"), ("APPDATA", "appdata"),
                          ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                          ("XDG_CACHE_HOME", "cache")]:
            folder = isolated / leaf
            folder.mkdir(parents=True, exist_ok=True)
            env[key] = str(folder)
        env["PYTHONUTF8"] = "1"
        version = subprocess.run([binary, "--version"], env=env, capture_output=True,
                                 text=True, encoding="utf-8", errors="replace", timeout=30)
        actual = version.stdout.strip()
        if version.returncode or not any(actual.startswith(version + ".") for version in SUPPORTED_GODOT):
            print(f"FAIL: tested Godot versions are {', '.join(SUPPORTED_GODOT)}; got {actual!r}", file=sys.stderr)
            return 1
        print(f"Godot: {actual}", flush=True)
        checks = [
            ("Import", [binary, "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"]),
            ("Level validator", [sys.executable, "tools/gen_levels.py"]),
            ("Existing regression", [binary, "--headless", "--path", str(ROOT), "res://tools/regression.tscn"]),
            ("Controls regression", [binary, "--headless", "--path", str(ROOT), "res://tools/control_regression.tscn"]),
            ("Box co-op regression", [binary, "--headless", "--path", str(ROOT), "res://tools/box_regression.tscn"]),
            ("Feedback regression", [binary, "--headless", "--path", str(ROOT), "res://tools/feedback_regression.tscn"]),
            ("Audio regression", [binary, "--headless", "--path", str(ROOT), "res://tools/audio_regression.tscn"]),
            ("Visual feedback regression", [binary, "--headless", "--path", str(ROOT), "res://tools/visual_feedback_regression.tscn"]),
            ("Atmosphere regression", [binary, "--headless", "--path", str(ROOT), "res://tools/atmosphere_regression.tscn"]),
            ("Box recovery regression", [binary, "--headless", "--path", str(ROOT), "res://tools/recovery_regression.tscn"]),
            ("UI regression", [binary, "--headless", "--path", str(ROOT), "res://tools/ui_regression.tscn"]),
            ("Session input regression", [binary, "--headless", "--path", str(ROOT), "res://tools/session_regression.tscn"]),
            ("Completion event ordering regression", [binary, "--headless", "--path", str(ROOT), "res://tools/completion_order_regression.tscn"]),
            ("Binding recovery regression", [binary, "--headless", "--path", str(ROOT), "res://tools/binding_regression.tscn"]),
            ("Save recovery regression", [binary, "--headless", "--path", str(ROOT), "res://tools/save_recovery_regression.tscn"]),
            ("Replay records regression", [binary, "--headless", "--path", str(ROOT), "res://tools/replay_regression.tscn"]),
            ("Replay transitions regression", [binary, "--headless", "--path", str(ROOT), "res://tools/replay_flow_regression.tscn"]),
            ("Menu replay regression", [binary, "--headless", "--path", str(ROOT), "res://tools/menu_replay_regression.tscn"]),
            ("Mechanism feedback regression", [binary, "--headless", "--path", str(ROOT), "res://tools/mechanism_feedback_regression.tscn"]),
            ("Enrichment cooperation and recovery", [sys.executable, "tools/run_enrichment_checks.py", "--godot", binary]),
        ]
        if not args.skip_smoke:
            checks.append(("10-level smoke", [binary, "--headless", "--path", str(ROOT), "--", "--smoke"]))
        if not args.skip_routes:
            checks.append(("10-level full-gem input replay", [sys.executable,
                           "tools/run_full_gem_routes.py", "--godot", binary, "--replay",
                           "--output", str(isolated / "full-gem-replay.json")]))
        for name, command in checks:
            print(f"\n=== {name} ===", flush=True)
            try:
                result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                        text=True, encoding="utf-8", errors="replace", timeout=240)
            except subprocess.TimeoutExpired:
                print(f"FAIL: {name} exceeded 240 seconds", file=sys.stderr)
                return 1
            output = result.stdout + result.stderr
            # Fresh Godot caches can log this before importing the project's font.
            # Verify a second import instead of hiding that error or accepting it.
            if name == "Import" and "ERROR: Error loading custom project font" in output:
                print(output, end="", flush=True)
                print("Rechecking import after the first font import...", flush=True)
                result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                        text=True, encoding="utf-8", errors="replace", timeout=240)
                output = result.stdout + result.stderr
            print(output, end="", flush=True)
            # Godot can print a script error without returning a failing exit status.
            error_lines = [line for line in output.splitlines()
                           if line.startswith(("SCRIPT ERROR:", "ERROR:"))]
            if result.returncode or error_lines:
                print(f"FAIL: {name} (exit {result.returncode})", file=sys.stderr)
                return 1
        print("\nAll checks passed. Test saves were isolated and removed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

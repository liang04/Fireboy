#!/usr/bin/env python3
"""Launch a co-op playtest with Godot 4.7 and disposable, isolated user data."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--level', type=int, choices=range(1, 14), required=True)
    parser.add_argument('--test-entry', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error('Godot not found; pass --godot /path/to/Godot (Windows: _console.exe).')
    with tempfile.TemporaryDirectory(prefix='fireboy-playtest-') as temporary:
        env = os.environ.copy()
        for key, leaf in [('HOME', 'home'), ('APPDATA', 'appdata'), ('XDG_DATA_HOME', 'data'),
                          ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            path = Path(temporary) / 'Fireboy-prototype-playtest' / leaf
            path.mkdir(parents=True)
            env[key] = str(path)
        version = subprocess.run([binary, '--version'], env=env, capture_output=True,
                                 text=True, encoding='utf-8', errors='replace', timeout=30)
        actual = version.stdout.strip()
        if version.returncode or not actual.startswith('4.7.'):
            parser.error(f'This project requires Godot 4.7 (4.7.x); got {actual!r}.')
        # Fresh source packages need imported fonts and the global script cache.
        imported = subprocess.run([binary, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                                  cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        log = imported.stdout + imported.stderr
        if 'ERROR: Error loading custom project font' in log:
            imported = subprocess.run([binary, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                                      cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
            log = imported.stdout + imported.stderr
        if imported.returncode or any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in log.splitlines()):
            print(log); return 1
        command = [binary, '--path', str(ROOT)]
        if args.test_entry:
            command += ['--headless', '--quit-after', '45']
        command += ['res://tools/prototype_launch.tscn', '--', f'--prototype-level={args.level}']
        print(f'Playtest level {args.level}. Close the game window to end this session; normal saves are untouched.', flush=True)
        return subprocess.run(command, cwd=ROOT, env=env).returncode

if __name__ == '__main__':
    raise SystemExit(main())

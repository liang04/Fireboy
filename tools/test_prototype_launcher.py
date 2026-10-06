#!/usr/bin/env python3
"""Verify all explicit playtest entries leave an ordinary-data sentinel untouched."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(); p.add_argument('--godot', required=True); a = p.parse_args()
with tempfile.TemporaryDirectory(prefix='prototype-launcher-check-') as directory:
    root = Path(directory); sentinel = root / 'progress.cfg'; sentinel.write_bytes(b'normal-player-save-do-not-touch\n')
    env = os.environ.copy()
    for key in ['HOME', 'APPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']: env[key] = str(root)
    before = {str(x.relative_to(root)): x.read_bytes() for x in root.rglob('*') if x.is_file()}
    for level in range(1, 14):
        result = subprocess.run([sys.executable, 'tools/play_prototypes.py', '--godot', a.godot,
                                 '--level', str(level), '--test-entry'], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=300)
        log = result.stdout + result.stderr
        assert result.returncode == 0 and f'[prototype-launch] L{level} isolated' in log, log
        assert not any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in log.splitlines()), log
        after = {str(x.relative_to(root)): x.read_bytes() for x in root.rglob('*') if x.is_file()}
        assert after == before, 'Normal user data was changed by prototype launch'
        print(f'[prototype-launcher] PASS L{level} entry; ordinary user data byte-identical')

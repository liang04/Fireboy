#!/usr/bin/env python3
"""Run all appended-level raw input completions, recoveries and counterexamples."""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
FILES = {
    'completion': ['level11_replay.json', 'level12_replay.json', 'level13_replays.json'],
    'recovery': ['level11_recovery_replay.json', 'level11_death_recovery_replay.json', 'level12_recovery_replay.json', 'level13_recovery_replays.json'],
    'scenario': ['level11_scenarios_replay.json', 'level12_scenarios_replay.json', 'level13_probes.json'],
}
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', default='godot')
    p.add_argument('--output-dir')
    a = p.parse_args()
    with tempfile.TemporaryDirectory(prefix='fireboy-appended-') as tmp:
        out = Path(a.output_dir).resolve() if a.output_dir else Path(tmp)
        out.mkdir(parents=True, exist_ok=True)
        for category, names in FILES.items():
            routes = []
            for name in names:
                routes += json.loads((ROOT / 'tools/new_levels' / name).read_text(encoding='utf-8'))
            assert {r['level'] for r in routes} == {11, 12, 13}, f'{category}: missing level'
            assert all('replay_tape' in r and r['replay_tape'] for r in routes), f'{category}: raw input tape required'
            if category != 'scenario':
                assert all(r.get('verify_store') and r.get('expected', {}).get('stars') == 3 for r in routes), 'Each completion needs exact 3-star and persisted-result assertions'
            target = Path(tmp) / (category + '.json')
            target.write_text(json.dumps(routes, ensure_ascii=False), encoding='utf-8')
            cmd = [sys.executable, 'tools/run_full_gem_routes.py', '--godot', a.godot,
                   '--skip-import', '--routes', str(target), '--output', str(out / (category + '.json'))]
            if category == 'scenario':
                cmd.append('--scenario')
            print('\n=== New level ' + category + ' ===', flush=True)
            result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=300)
            log = result.stdout + result.stderr
            print(log, end='', flush=True)
            if result.returncode or any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in log.splitlines()):
                return 1
        # Observe the same immutable death tape: genuine feet-first contact,
        # one natural respawn, K still open, and no stale-pool death at spawn.
        env = os.environ.copy()
        for key in ['HOME', 'APPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
            folder = Path(tmp) / 'Fireboy-optimization-tests' / key
            folder.mkdir(parents=True)
            env[key] = str(folder)
        probe_output = out / 'hazard_respawn.json'
        cmd = [shutil.which(a.godot) or a.godot, '--headless', '--path', str(ROOT),
               '--fixed-fps', '60', 'res://tools/new_levels/level11_death_probe.tscn', '--',
               '--routes=res://tools/new_levels/level11_death_recovery_replay.json',
               '--output=' + str(probe_output)]
        result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        print(log, end='', flush=True)
        if result.returncode or not probe_output.exists() or any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in log.splitlines()):
            return 1
        probe = json.loads(probe_output.read_text())
        if not probe.get('runs') or not all(r.get('passed') and r.get('hazard_geometry_probe', {}).get('passed') for r in probe['runs']):
            return 1
    print('All new-level input checks passed.')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())

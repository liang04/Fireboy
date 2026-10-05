#!/usr/bin/env python3
"""Focused temporal, recovery, alternative-order and save-isolation checks."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(); p.add_argument('--godot', required=True); a = p.parse_args()
    with tempfile.TemporaryDirectory(prefix='fireboy-prototype-checks-') as directory:
        root = Path(directory); env = os.environ.copy()
        for key, leaf in [('HOME','home'),('APPDATA','appdata'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
            path = root/'Fireboy-optimization-tests'/leaf; path.mkdir(parents=True); env[key] = str(path)
        replay = []
        for name in ['level03_vault_last_replay','level03_recovery_replay','level04_recovery_replay','level08_replay_b_first','level08_recovery_replay']:
            replay += json.loads((ROOT/f'tools/enrichment/prototypes/{name}.json').read_text())
        replay_file = root/'alternative-recovery-replays.json'; replay_file.write_text(json.dumps(replay))
        commands = [[sys.executable,'tools/test_prototype_static.py'],
                    [sys.executable,'tools/enrichment/prototypes/level03_static.py'],
                    [sys.executable,'tools/enrichment/prototypes/level08_static.py']]
        for scene in ['delayed_plate_regression','reversible_route_regression','prototype_migration_regression']:
            commands.append([a.godot,'--headless','--path',str(ROOT),'--fixed-fps','60',f'res://tools/{scene}.tscn'])
        commands += [[sys.executable,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--replay','--routes',str(replay_file),'--output',str(root/'replay-results.json')],
                     [sys.executable,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--scenario','--routes','tools/enrichment/prototypes/level03_direct.json','--output',str(root/'direct-result.json')],
                     [sys.executable,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--scenario','--routes','tools/enrichment/prototypes/level08_scenarios_replay.json','--output',str(root/'bridge-scenarios.json')],
                     [sys.executable,'tools/test_prototype_launcher.py','--godot',a.godot]]
        for command in commands:
            print('\n=== '+' '.join(command)+' ===',flush=True)
            run = subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=300)
            log=run.stdout+run.stderr; print(log,end='',flush=True)
            if run.returncode or any(line.startswith(('SCRIPT ERROR:','ERROR:')) for line in log.splitlines()):return 1
    print('All prototype checks passed.');return 0
if __name__=='__main__':raise SystemExit(main())

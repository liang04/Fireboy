#!/usr/bin/env python3
"""Record real Input tapes, then verify exact playback, results UI and isolated saves.

Run after generating levels.gd. This never changes gameplay state: controller
commands go through tools/full_gem_routes.gd, and replay uses only Input masks.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--skip-import', action='store_true')
    args = parser.parse_args()
    evidence = HERE / 'evidence'
    evidence.mkdir(exist_ok=True)
    def run(source, destination, scenario=False):
        cmd = [sys.executable, str(ROOT/'tools/run_full_gem_routes.py'),
               '--godot', args.godot, '--routes', str(source), '--output', str(destination)]
        if args.skip_import: cmd.append('--skip-import')
        if scenario: cmd.append('--scenario')
        result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
        print(result.stdout, end='')
        if result.returncode:
            print(result.stderr, end='')
            raise SystemExit(result.returncode)
        return read(destination)
    tapes = []
    names = [f'{prefix}_{number:02d}' for prefix in ('controllers','alternate','recovery')
             for number in (5,6,7)] + ['underside_recovery_05']
    for stem in names:
        number = int(stem[-2:])
        source = HERE/f'{stem}.json'
        report = run(source, evidence/f'{stem}.json')
        entry = report['runs'][0]
        assert all(entry[key] for key in ('passed','completed','all_gems','within_par',
                   'snapshot_consistent','store_verified','store_consistent'))
        assert entry['stars'] == 3 and entry['deaths'] == 0 and entry['box_resets'] == 0
        tape = dict(level=number, name=stem, verify_store=True,
                    expected={key:entry[key] for key in ('frames','red','blue','red_total',
                              'blue_total','deaths','box_resets','stars')},
                    replay_tape=entry['input_tape'])
        assert sum(s['frames'] for s in tape['replay_tape']) == entry['frames']
        write(HERE/f'replay_{stem}.json', [tape])
        tapes.append(tape)
    write(HERE/'replays.json', tapes)
    run(HERE/'replays.json', evidence/'replays.json')
    scenarios = []
    for stem in ('paused_05','underside_05','clear_underside_05','blocked_06','main_path_07'):
        source = HERE/f'{stem}.json'
        original = read(source)[0]
        report = run(source, evidence/f'{stem}.json', scenario=True)
        entry = report['runs'][0]
        assert entry['passed']
        if stem == 'main_path_07':
            assert entry['completed'] and not entry['all_gems'] and entry['frames'] < 600
        tape = dict(level=original['level'], name=original['name'],
                    scenario=dict(original['scenario'],frames=entry['frames']),
                    replay_tape=entry['input_tape'])
        if not entry['completed']:
            # Controller terminal checkpoints record their result before the
            # outer physics tick appends one final idle segment. Bound playback
            # to the observed checkpoint, preserving every preceding Input.
            tape['max_frames'] = entry['frames']
            remaining = entry['frames']
            bounded = []
            for segment in tape['replay_tape']:
                if remaining <= 0: break
                count = min(remaining, int(segment['frames']))
                bounded.append(dict(segment,frames=count))
                remaining -= count
            assert remaining == 0
            tape['replay_tape'] = bounded
        scenarios.append(tape)
    write(HERE/'scenario_replays.json', scenarios)
    run(HERE/'scenario_replays.json', evidence/'scenario_replays.json', scenario=True)
    print('PASS: ten full-gem 3-star tapes; all completion snapshots and persisted saves agree.')
    print('PASS: paused freight, blocked and cleared underside, portal keeper retry and optional dry promenade scenarios.')

if __name__ == '__main__':
    main()

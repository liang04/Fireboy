#!/usr/bin/env python3
"""Capture and verify L12 Input-only completion, recovery and adversarial tapes."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output-dir', type=Path, default=Path('/tmp/fireboy-level12'))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    def run(source, scenario=False):
        output = args.output_dir / (source.stem + '_evidence.json')
        command = [sys.executable, str(ROOT / 'tools/run_full_gem_routes.py'),
                   '--godot', args.godot, '--skip-import', '--levels', '12',
                   '--routes', str(source), '--output', str(output)]
        if scenario:
            command.append('--scenario')
        subprocess.run(command, cwd=ROOT, check=True)
        return read(output)

    completions = []
    for stem in ['level12_route', 'level12_recovery_route', 'level12_bridge_recovery_route']:
        entry = run(HERE / f'{stem}.json')['runs'][0]
        assert all(entry[key] for key in ['passed', 'completed', 'all_gems', 'within_par',
                                          'snapshot_consistent', 'store_verified', 'store_consistent'])
        assert entry['stars'] == 3 and entry['deaths'] == entry['box_resets'] == 0
        tape = dict(level=12, name=stem, verify_store=True,
                    expected={key: entry[key] for key in ['frames', 'deaths', 'box_resets',
                              'red', 'red_total', 'blue', 'blue_total', 'stars']},
                    replay_tape=entry['input_tape'])
        assert sum(segment['frames'] for segment in tape['replay_tape']) == entry['frames']
        completions.append(tape)
    write(HERE / 'level12_replay.json', completions[:1])
    write(HERE / 'level12_recovery_replay.json', completions[1:])

    source = HERE / 'level12_scenarios.json'
    scenarios = []
    for original, entry in zip(read(source), run(source, True)['runs'], strict=True):
        assert entry['passed']
        expected = copy.deepcopy(original['scenario'])
        expected.pop('reason_prefix', None)  # Controller timeouts are replay checkpoints.
        expected['frames'] = entry['frames']
        remaining = entry['frames']
        bounded = []
        for segment in entry['input_tape']:
            if remaining <= 0:
                break
            count = min(remaining, int(segment['frames']))
            bounded.append(dict(segment, frames=count))
            remaining -= count
        assert remaining == 0
        scenarios.append(dict(level=12, name=original['name'], scenario=expected,
                              max_frames=entry['frames'], replay_tape=bounded))
    write(HERE / 'level12_scenarios_replay.json', scenarios)
    run(HERE / 'level12_replay.json')
    run(HERE / 'level12_recovery_replay.json')
    run(HERE / 'level12_scenarios_replay.json', True)
    print('PASS: L12 three full-gem 3-star persisted completions and five adversarial Input tapes.')


if __name__ == '__main__':
    main()

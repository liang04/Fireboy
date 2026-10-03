#!/usr/bin/env python3
"""Run real-input full-gem routes against fresh levels, isolating all player saves."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--levels', default='', help='Comma-separated level numbers, e.g. 1,8,10')
    parser.add_argument('--routes', help='Alternate controller-route or replay-tape JSON')
    parser.add_argument('--scenario', action='store_true', help='Run explicit adversarial scenarios, not completion proofs')
    parser.add_argument('--replay', action='store_true', help='Replay checked-in action tapes without waypoint logic')
    parser.add_argument('--skip-import', action='store_true', help='Skip the initial Godot import (for an already imported project)')
    parser.add_argument('--output', default=str(Path(tempfile.gettempdir()) / 'full-gem-routes-results.json'))
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error('Godot not found. Pass --godot /path/to/Godot.')
    source = Path(args.routes) if args.routes else ROOT / 'tools' / (
        'full_gem_route_replay.json' if args.replay else 'full_gem_routes.json')
    source = source.resolve()
    route_data = json.loads(source.read_text(encoding='utf-8'))
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    requested = {int(x) for x in args.levels.split(',') if x}
    available = {int(route['level']) for route in route_data}
    if requested - available:
        parser.error(f'No routes for levels {sorted(requested - available)}')
    selected = requested or available
    sources = [ROOT / 'project.godot', *sorted((ROOT / 'scripts').rglob('*.gd')),
               *sorted((ROOT / 'scenes').glob('*.tscn')), ROOT / 'tools/full_gem_routes.gd',
               ROOT / 'tools/full_gem_routes.tscn', ROOT / 'tools/run_full_gem_routes.py',
               ROOT / 'tools/gen_levels.py', *sorted((ROOT / 'tools/enrichment').glob('*.py')), source]
    def source_hashes():
        return {str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path):
                hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    if args.scenario:
        sources += [ROOT / 'tools/coop_scenarios.gd', ROOT / 'tools/coop_scenarios.tscn']
    initial_hashes = source_hashes()
    # Temporary results ensure a stale report cannot disguise a failed invocation.
    with tempfile.TemporaryDirectory(prefix='fireboy-routes-') as temporary:
        env = os.environ.copy()
        for key, leaf in [('HOME', 'home'), ('APPDATA', 'appdata'), ('XDG_DATA_HOME', 'data'),
                          ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            path = Path(temporary) / 'Fireboy-optimization-tests' / leaf
            path.mkdir(parents=True)
            env[key] = str(path)
        if not args.skip_import:
            import_command = [binary, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit']
            try:
                imported = subprocess.run(import_command, cwd=ROOT, env=env, capture_output=True,
                                          text=True, encoding='utf-8', errors='replace', timeout=300)
                import_log = imported.stdout + imported.stderr
                if 'ERROR: Error loading custom project font' in import_log:
                    print('First import needed a second pass after importing the project font.')
                    imported = subprocess.run(import_command, cwd=ROOT, env=env, capture_output=True,
                                              text=True, encoding='utf-8', errors='replace', timeout=300)
                    import_log = imported.stdout + imported.stderr
            except subprocess.TimeoutExpired:
                print('FAIL: Godot import exceeded 300 seconds')
                return 1
            if imported.returncode or any(line.startswith(('SCRIPT ERROR:', 'ERROR:'))
                                          for line in import_log.splitlines()):
                print(import_log, end='')
                print('FAIL: Godot import failed')
                return 1
            print('Godot import passed.')
        report_path = Path(temporary) / 'results.json'
        command = [binary, '--headless', '--path', str(ROOT), '--fixed-fps', '60',
                   ('res://tools/coop_scenarios.tscn' if args.scenario else 'res://tools/full_gem_routes.tscn'), '--', f'--routes={source}',
                   f'--output={report_path}']
        if args.levels:
            command.append(f'--levels={args.levels}')
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                    text=True, encoding='utf-8', errors='replace', timeout=300)
        except subprocess.TimeoutExpired:
            print('FAIL: route run exceeded 300 seconds')
            return 1
        log = result.stdout + result.stderr
        print(log, end='')
        errors = any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in log.splitlines())
        if not report_path.exists():
            print('FAIL: Godot produced no result report')
            return 1
        report = json.loads(report_path.read_text(encoding='utf-8'))
        final_hashes = source_hashes()
        report['source_sha256'] = initial_hashes
        report['sources_changed_during_run'] = initial_hashes != final_hashes
        errors = errors or report['sources_changed_during_run']
        report['route_file'] = str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source)
        report['verification'] = 'Fresh Level; real Player physics; Input actions only; 60 Hz; isolated saves'
        report['engine_log_has_errors'] = errors
        # Replays reference the immutable checked-in input tape; don't duplicate it in evidence.
        for run in report.get('runs', []):
            if run.get('mode') == 'input_replay':
                run['input_frames'] = sum(int(segment['frames']) for segment in run.pop('input_tape'))
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'Evidence saved to {output}')
        runs = report.get('runs', [])
        complete = {int(run['level']) for run in runs} == selected
        return 0 if (result.returncode == 0 and not errors and complete and all(run.get('passed') for run in runs)) else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Current seven-level cooperation, recovery and deliberate-mistake raw replays."""
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',default='godot');p.add_argument('--output-dir');a=p.parse_args()
    with tempfile.TemporaryDirectory(prefix='fireboy-enrichment-') as tmp:
        out=Path(a.output_dir).resolve() if a.output_dir else Path(tmp)
        out.mkdir(parents=True,exist_ok=True)
        def read(path): return json.loads((ROOT/path).read_text())
        scenarios=read('tools/enrichment/seven_intro/scenario_replay.json')
        scenarios+=read('tools/enrichment/seven_middle/scenario_replays.json')
        scenarios+=read('tools/enrichment/seven_final/solo_bypass_regression.json')
        # Prototype cooperation counterexamples remain current and unchanged.
        for suffix in ['03','04']:
            scenarios+=read(f'tools/enrichment/prototypes/level{suffix}_scenarios.json')
        recoveries=read('tools/enrichment/seven_intro/replays.json')
        recoveries+=read('tools/enrichment/seven_middle/replays.json')
        for path in sorted((ROOT/'tools/enrichment/seven_final').glob('replay_*.json')):
            recoveries+=json.loads(path.read_text())
        recoveries+=read('tools/enrichment/prototypes/level04_recovery_replay.json')
        scenario_file=Path(tmp)/'scenarios.json';scenario_file.write_text(json.dumps(scenarios))
        recovery_file=Path(tmp)/'recoveries.json';recovery_file.write_text(json.dumps(recoveries))
        py=sys.executable
        commands=[
          [py,'tools/test_enrichment_static.py'],
          [py,'tools/enrichment/seven_middle/test_layouts.py'],
          [py,'tools/enrichment/verify_late_geometry.py'],
          [py,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--scenario','--routes',str(scenario_file),'--output',str(out/'coop_scenarios.json')],
          [py,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--routes',str(recovery_file),'--output',str(out/'recovery_routes.json')],
          [py,'tools/enrichment/run_late_probes.py','--godot',a.godot,'--routes','tools/enrichment/seven_final/probes_replay.json','--output',str(out/'late_probes.json')],
        ]
        for cmd in commands:
            print('\n=== '+' '.join(cmd[1:])+' ===',flush=True)
            result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=300)
            log=result.stdout+result.stderr;print(log,end='',flush=True)
            if result.returncode or any(x.startswith(('SCRIPT ERROR:','ERROR:')) for x in log.splitlines()):return 1
    print('All enrichment checks passed.');return 0
if __name__=='__main__':raise SystemExit(main())

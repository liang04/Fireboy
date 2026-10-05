#!/usr/bin/env python3
"""Run targeted cooperation and recovery checks against the combined ten levels."""
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',default='godot');p.add_argument('--output-dir');a=p.parse_args()
    with tempfile.TemporaryDirectory(prefix='fireboy-enrichment-') as tmp:
        out=Path(a.output_dir).resolve() if a.output_dir else Path(tmp)
        out.mkdir(parents=True,exist_ok=True)
        scenarios=[];recoveries=[]
        for suffix in ['01_06','02','07']:
            scenarios+=json.loads((ROOT/f'tools/enrichment/scenarios_{suffix}.json').read_text())
        for suffix in ['03','04']:
            scenarios+=json.loads((ROOT/f'tools/enrichment/prototypes/level{suffix}_scenarios.json').read_text())
        for n in [2,7,10]:recoveries+=json.loads((ROOT/f'tools/enrichment/recovery_{n:02d}.json').read_text())
        recoveries+=json.loads((ROOT/'tools/enrichment/prototypes/level04_recovery_replay.json').read_text())
        scenario_file=Path(tmp)/'scenarios.json';scenario_file.write_text(json.dumps(scenarios))
        recovery_file=Path(tmp)/'recoveries.json';recovery_file.write_text(json.dumps(recoveries))
        py=sys.executable
        commands=[
          [py,'tools/test_enrichment_static.py'],
          [py,'tools/enrichment/verify_late_geometry.py'],
          [py,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--scenario','--routes',str(scenario_file),'--output',str(out/'coop_scenarios.json')],
          [py,'tools/run_full_gem_routes.py','--godot',a.godot,'--skip-import','--routes',str(recovery_file),'--output',str(out/'recovery_routes.json')],
          [py,'tools/enrichment/run_lift_coop_probes.py','--godot',a.godot,'--levels','5','--skip-import','--output',str(out/'lift_probes.json')],
          [py,'tools/enrichment/run_late_probes.py','--godot',a.godot,'--routes','tools/enrichment/probe_replay_late.json','--output',str(out/'late_probes.json')],
        ]
        for cmd in commands:
            print('\n=== '+' '.join(cmd[1:])+' ===',flush=True)
            result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=300)
            log=result.stdout+result.stderr;print(log,end='',flush=True)
            if result.returncode or any(x.startswith(('SCRIPT ERROR:','ERROR:')) for x in log.splitlines()):return 1
    print('All enrichment checks passed.');return 0
if __name__=='__main__':raise SystemExit(main())

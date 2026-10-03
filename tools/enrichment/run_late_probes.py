#!/usr/bin/env python3
"""Run read-only adversarial observations with actual Input-only character routes."""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot',default='godot')
    p.add_argument('--routes',default='tools/enrichment/probes_late.json')
    p.add_argument('--output',default='tools/enrichment/probe_evidence_late.json')
    args=p.parse_args()
    source=(ROOT / args.routes).resolve()
    files=[ROOT/'project.godot',*sorted((ROOT/'scripts').rglob('*.gd')),ROOT/'tools/full_gem_routes.gd',*sorted((ROOT/'tools/enrichment').glob('*.gd')),source]
    def hashes(): return {str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in files}
    before=hashes()
    with tempfile.TemporaryDirectory(prefix='fireboy-late-probes-') as tmp:
        env=os.environ.copy()
        for key in ['HOME','APPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
            directory=pathlib.Path(tmp)/'Fireboy-optimization-tests'/key
            directory.mkdir(parents=True)
            env[key]=str(directory)
        out=pathlib.Path(tmp)/'probes.json'
        cmd=[shutil.which(args.godot) or args.godot,'--headless','--path',str(ROOT),'--fixed-fps','60','res://tools/enrichment/late_probe.tscn','--',f'--routes={source}',f'--output={out}']
        run=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True,timeout=300)
        log=run.stdout+run.stderr
        print(log,end='')
        if not out.exists(): return 1
        data=json.loads(out.read_text())
        data['source_sha256']=before
        data['sources_changed_during_run']=before != hashes()
        data['engine_log_has_errors']=any(x.startswith(('ERROR:','SCRIPT ERROR:')) for x in log.splitlines())
        data['route_file']=str(source.relative_to(ROOT))
        (ROOT/args.output).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
        return int(bool(run.returncode or data['sources_changed_during_run'] or data['engine_log_has_errors'] or not all(x['passed'] for x in data['runs'])))

if __name__=='__main__': raise SystemExit(main())

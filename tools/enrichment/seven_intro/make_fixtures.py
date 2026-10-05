"""Convert observed controller evidence into strict, input-only replay fixtures."""
import argparse
import json
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('controllers',type=Path);p.add_argument('evidence',type=Path);p.add_argument('output',type=Path)
a=p.parse_args();controllers=json.loads(a.controllers.read_text());runs=json.loads(a.evidence.read_text())['runs']
assert len(controllers)==len(runs)
replays=[]
for source,run in zip(controllers,runs):
    assert run['passed'],(source.get('name'),run['reason'])
    r={'level':source['level'],'name':source.get('name',''),'replay_tape':run['input_tape']}
    if 'scenario' in source:
        # The scenario runner records its final released-input frame after the
        # observation snapshot. Playback owns the full captured tape length.
        r['scenario']=dict(source['scenario'],frames=sum(s['frames'] for s in run['input_tape']))
        r['scenario']['reason_prefix']='input tape exhausted'
    else:
        r['verify_store']=True
        r['expected']={k:run[k] for k in ('frames','deaths','box_resets','red','red_total','blue','blue_total','stars')}
    replays.append(r)
a.output.write_text(json.dumps(replays,ensure_ascii=False,indent=2)+'\n')

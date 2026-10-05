#!/usr/bin/env python3
"""Bound the prototype scope and reject malformed temporal mechanism data."""
import hashlib
import json
from copy import deepcopy
from pathlib import Path
import gen_levels as g
from enrichment.prototype_validator import project

ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / 'tools/enrichment/prototypes/baseline_contract.json').read_text())
changed = {3, 4, 8}
for n, lv in enumerate(g.LEVELS, 1):
    old = contract[str(n)]
    if n in changed:
        assert lv['revision'] == old['revision'] + 1, f'L{n}: content revision must increment exactly once'
    else:
        actual = hashlib.sha256(json.dumps(lv, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        assert actual == old['sha256'], f'L{n}: unapproved content change'
replays = json.loads((ROOT / 'tools/full_gem_route_replay.json').read_text())
for route in replays:
    if route['level'] not in changed:
        digest = hashlib.sha256(json.dumps(route, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        assert digest == contract[str(int(route['level']))]['replay_sha256'], 'Unchanged level replay was modified'
print('[prototype-static] PASS only3/4/8 changed; other7 data and exact old raw replays intact')

for number in [4, 8]:
    lv = g.LEVELS[number - 1]
    projected, errors, temporal = project(lv['grid'], lv['objects'])
    assert temporal and not errors, errors
    assert not any(o['type'] in ['delayed_plate', 'reversible_route'] for o in projected)
print('[prototype-static] PASS valid temporal data explicitly projected as geometry upper bounds')

base = g.LEVELS[3]
for delay in [-1, 0, '6', 999]:
    assert project(base['grid'], [dict(type='delayed_plate', cell=[1, 1], delay_seconds=delay)])[1]
for cell in [[-1, 1], [999, 1], [1], None]:
    assert project(base['grid'], [dict(type='delayed_plate', cell=cell)])[1]
route = next(o for o in g.LEVELS[7]['objects'] if o['type'] == 'reversible_route')
for field, value in [('initial_state', 2), ('switches', []), ('gates', [])]:
    bad = deepcopy(route); bad[field] = value
    assert project(g.LEVELS[7]['grid'], [bad])[1]
for field, value in [('open_state', 2), ('height', -1), ('cell', [999, 1])]:
    bad = deepcopy(route); bad['gates'][0][field] = value
    assert project(g.LEVELS[7]['grid'], [bad])[1]
print('[prototype-static] PASS malformed timer and route declarations rejected')
print('[prototype-static] NOTE geometry projection does not prove timed or mutually exclusive traversal')

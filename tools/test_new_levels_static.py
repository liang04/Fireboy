#!/usr/bin/env python3
"""Append-only contract: protect every existing level and both original tapes."""
import hashlib
import json
from pathlib import Path
import gen_levels as g
ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / 'tools/new_levels/baseline_contract.json').read_text())
def digest(data):
    return hashlib.sha256(data).hexdigest()
assert len(g.LEVELS) == 13
for n, level in enumerate(g.LEVELS[:10], 1):
    old = contract['levels'][str(n)]
    assert digest(json.dumps(level, sort_keys=True, separators=(',', ':')).encode()) == old['sha256'], f'L{n}: old content changed'
    assert level['revision'] == old['revision'], f'L{n}: revision changed'
for path, expected in contract['files'].items():
    assert digest((ROOT / path).read_bytes()) == expected, f'preserved bytes changed: {path}'
for n, level in enumerate(g.LEVELS[10:], 11):
    assert level['revision'] == 1, f'L{n}: new content starts at revision 1'
    assert level['par_time'] > 0
    assert not any('【致命】' in e for e in g.validate(level, n-1)), f'L{n}: static failure'
print('[new-levels-static] PASS 13 levels; all original level data, revisions, builders and input tapes byte-identical')
# Regression guards for failure paths that ordinary reachability cannot model.
assert all(o.get('open_up') for o in g.LEVELS[10]['objects'] if o['type'] == 'door'), 'L11 open shutters must not seal the lower respawn hub'
l12 = g.LEVELS[11]
receiver = next(o for o in l12['objects'] if o['type'] == 'plate' and o['channel'] == 'C')
assert g.plate_surfaces(receiver) == {(x, 14) for x in range(37, 53)}, 'L12 over-pushed cargo must still power C at the upper wall'
assert all(l12['grid'][19][x] == '#' for x in range(19, 52)), 'L12 lower-right cargo must have a continuous return apron'
assert l12['grid'][20][1] == '~' and l12['grid'][19][52] == '~', 'L12 outer cargo wall traps need visible reclaim pockets'
l13 = g.LEVELS[12]
assert any(o['type'] == 'double_plate' and o.get('channel') == 'R' for o in l13['objects']), 'L13 R must permanently latch'
assert any(o['type'] == 'lever' and o.get('channel') == 'S' for o in l13['objects']), 'L13 wrong-side actor needs an independent interior escape switch'
print('[new-levels-static] PASS respawn, cargo return/wall reclaim and permanent objective escape contracts')

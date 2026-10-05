#!/usr/bin/env python3
"""Focused L3 topology checks; actual movement is covered by paired input tapes."""
from copy import deepcopy
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import gen_levels as g
from enrichment.relay_validator import solve

level = g.LEVELS[2]
assert len(level['grid']) == 24 and {len(row) for row in level['grid']} == {68}
assert level['revision'] == g.LEVEL_REVISION[3] + 2
assert level['par_time'] == 65.0
assert level['grid'][21][18:26] == '~' * 8
assert level['grid'][12][32:40] == '^' * 8
assert solve(level['grid'], level['objects'], vars(g)) is not None
for channel in ('C', 'D', 'E'):
    broken = deepcopy(level)
    broken['objects'] = [o for o in broken['objects'] if not (
        o.get('channel') == channel and o['type'] in ('plate', 'lever'))]
    assert solve(broken['grid'], broken['objects'], vars(g)) is None, channel
# V remains a real optional branch: withholding its latch preserves completion.
without_v = [o for o in level['objects'] if not (
    o.get('channel') == 'V' and o['type'] == 'double_plate')]
assert solve(level['grid'], without_v, vars(g)) is not None
assert {'type':'gem', 'cell':[44,11], 'color':'blue'} in level['objects']
assert {'type':'gem', 'cell':[42,20], 'color':'red'} in level['objects']
# The reused roof still seals the vault; the dry switchback cannot drop inside.
assert level['grid'][17][61:67] == '#' * 6
assert level['grid'][19][58:61] == level['grid'][15][58:61] == '###'
assert not any('【致命】' in message for message in g.validate(level, 2))
print('[level03-static] PASS original split and C/D/E dependency, optional V, dry return stairs, crossed gems, revision and par')

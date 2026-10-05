#!/usr/bin/env python3
"""Structural checks complement (and never replace) L8 raw-input route proofs."""
from pathlib import Path
import importlib.util
import json
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_levels


def check():
    level = gen_levels.LEVELS[7]
    grid = level['grid']
    mechanism = next(o for o in level['objects'] if o['type'] == 'reversible_route')
    gates = mechanism['gates']
    assert len(gates) == 2 and {g['open_state'] for g in gates} == {0, 1}
    assert {tuple(s['cell']) for s in mechanism['switches']} == {(12, 19), (12, 10), (44, 19), (44, 10)}
    assert not any('element' in s or 'select_state' in s for s in mechanism['switches'])
    # Permanent, impassable upper floor reaches the right border. A player cannot
    # drop at the far landing into B, bypassing the remote partner's next route.
    assert all(grid[11][x] in '#=' for x in range(8, len(grid[0])))
    assert all(grid[20][x] in '#=' for x in range(1, len(grid[0]) - 1))
    for gate in gates:
        x, y = gate['cell']
        assert grid[y - 1][x] in '#='
        assert grid[y + gate['height']][x] in '#='
        assert all(grid[row][x] == '.' for row in range(y, y + gate['height']))
        for station in mechanism['switches']:
            assert abs(station['cell'][0] - x) >= 8
    assert not any(c in '~^*' for row in grid for c in row)
    assert not any(o['type'] in ('box', 'moving_platform') for o in level['objects'])
    pad = next(o for o in level['objects'] if o['type'] == 'double_plate')
    assert pad['cells'] == [[43, 10], [43, 19]]
    assert all(cell[0] > gates[0]['cell'][0] for cell in pad['cells'])
    assert next(o for o in level['objects'] if o['type'] == 'door')['channel'] == pad['channel']
    for color in ('red', 'blue'):
        gems = [o for o in level['objects'] if o['type'] == 'gem' and o['color'] == color]
        assert any(o['cell'][1] == 10 and o['cell'][0] > 26 for o in gems)
        assert any(o['cell'][1] == 19 and o['cell'][0] > 26 for o in gems)
    baseline = json.loads((Path(__file__).parent / 'baseline_contract.json').read_text())
    # Generic contract suite owns exact baseline revision/unchanged-level assertions.
    assert level['par_time'] == 90.0
    for order in ('a', 'b'):
        tape = json.loads((Path(__file__).parent / f'level08_replay_{order}_first.json').read_text())[0]
        assert tape['verify_store'] and tape['expected']['deaths'] == tape['expected']['box_resets'] == 0
        assert tape['expected']['red'] == tape['expected']['blue'] == 5
        assert sum(part['frames'] for part in tape['replay_tape']) == tape['expected']['frames']
    print('[L8 static] complementary bridge routes, fixed support, separated remote keys, two replay orders PASS')


if __name__ == '__main__':
    check()

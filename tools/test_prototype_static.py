#!/usr/bin/env python3
"""Preserve the shipped prototypes while enriching the other seven levels."""
import hashlib
import json
import re
from copy import deepcopy
from pathlib import Path
import gen_levels as g
from enrichment.prototype_validator import project

ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / 'tools/enrichment/seven_baseline_contract.json').read_text())
changed = {1, 2, 5, 6, 7, 9, 10}
preserved = {3, 4, 8}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def route_entries(path):
    """Retain each entry's actual bytes as well as its decoded content."""
    text = path.read_bytes().decode('utf-8')
    values = json.loads(text)
    assert isinstance(values, list) and len(values) == 10, f'{path.name}: exactly ten routes required'
    decoder = json.JSONDecoder()
    position = text.index('[') + 1
    entries = {}
    for value in values:
        while text[position].isspace() or text[position] == ',':
            position += 1
        decoded, end = decoder.raw_decode(text, position)
        assert decoded == value
        number = int(value['level'])
        assert number == value['level'] and number not in entries, f'{path.name}: duplicate/invalid level'
        entries[number] = (value, text[position:end].encode('utf-8'))
        position = end
    assert set(entries) == changed | preserved, f'{path.name}: every level needs one route'
    return entries


assert len(g.LEVELS) == 10, 'The seven-level enrichment must preserve level count/order'
emitted = (ROOT / 'scripts/levels/levels.gd').read_bytes()
for n, lv in enumerate(g.LEVELS, 1):
    old = contract[str(n)]
    if n in changed:
        assert lv['revision'] == old['revision'] + 1, f'L{n}: content revision must increment exactly once'
    else:
        assert lv['revision'] == old['revision'], f'L{n}: preserved revision changed'
        assert digest(lv) == old['sha256'], f'L{n}: shipped prototype data changed'
        builder = ROOT / f'tools/enrichment/level_{n:02d}.py'
        assert hashlib.sha256(builder.read_bytes()).hexdigest() == old['builder_sha256'], f'L{n}: builder bytes changed'
        block = re.search(rb'^static func _level_%02d\(\).*?(?=^static func _level_|\Z)' % n,
                          emitted, re.M | re.S)
        assert block is not None, f'L{n}: generated declaration missing'
        assert hashlib.sha256(block.group()).hexdigest() == old['generated_block_sha256'], f'L{n}: generated data bytes changed'

for filename, prefix in [('full_gem_route_replay.json', 'replay'), ('full_gem_routes.json', 'controller')]:
    entries = route_entries(ROOT / 'tools' / filename)
    for n in preserved:
        route, raw = entries[n]
        old = contract[str(n)]
        assert digest(route) == old[prefix + '_sha256'], f'L{n}: preserved {prefix} content changed'
        assert hashlib.sha256(raw).hexdigest() == old[prefix + '_bytes_sha256'], f'L{n}: preserved {prefix} bytes changed'
print('[prototype-static] PASS seven revisions advance once; L3/L4/L8 data, builders and both route forms remain byte-identical')

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

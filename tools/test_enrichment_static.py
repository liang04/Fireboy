#!/usr/bin/env python3
"""Regression fixtures for sequential relay, box elevators and ceiling geometry."""
from copy import deepcopy
import gen_levels as g
from enrichment.relay_validator import solve

def check(value, message):
    assert value, message
    print('[enrichment-static] PASS ' + message)

lv=g.LEVELS[2]
check(solve(lv['grid'],lv['objects'],vars(g)) is not None,'two successive keepers have a real checkpoint-state path')
for channel in ['C','D','E']:
    broken=deepcopy(lv)
    broken['objects']=[o for o in broken['objects'] if not (o.get('channel')==channel and o['type'] in ['plate','lever'])]
    check(solve(broken['grid'],broken['objects'],vars(g)) is None,'removing relay controller '+channel+' breaks the staged route')
# No fallback may silently invent box transportation.
check(solve(g.LEVELS[6]['grid'],g.LEVELS[6]['objects'],vars(g)) is None,'relay fallback refuses box puzzles outside its model')
# A player cannot fall through the bridge roof into the lower corridor.
lv=g.LEVELS[0];b,v,fs,d=g.build_block_maps(lv['grid'],lv['objects'],'water')
check(not g._can_move(b,v,36,16,41,20,5),'descending jump cannot pass through a solid shelf')
check((47,20) not in g.compute_reach(lv['grid'],lv['objects'],'water',set()),'teaching lower exit is unavailable with all gates closed')
# Box transport is supported only by an actual active, swept-clear platform.
lv=g.LEVELS[6]; active={'A','B','D'}
reach=g.compute_reach(lv['grid'],lv['objects'],'fire',active)|g.compute_reach(lv['grid'],lv['objects'],'water',active)
box=next(o for o in lv['objects'] if o['type']=='box')
positions=g.box_reachable(lv['grid'],lv['objects'],box['cell'],reach,active)
check((32,12) in positions,'box can ride the real lift to the delivery plate')
check((41,11) not in positions,'lift cannot put the box on the final raised keeper plate')
without=[o for o in lv['objects'] if o['type']!='moving_platform']
check((32,12) not in g.box_reachable(lv['grid'],without,box['cell'],reach,active),'removing the lift removes the box ascent')
blocked=deepcopy(lv);rows=[list(r) for r in blocked['grid']]
for x in range(24,29):rows[15][x]='#'
blocked['grid']=[''.join(r) for r in rows]
check((32,12) not in g.box_reachable(blocked['grid'],blocked['objects'],box['cell'],reach,active),'a solid obstruction invalidates lift cargo transport')
# Existing static model must now understand a held-gate box handoff.
lv=g.LEVELS[3];active,_=g.solve_channels(lv['grid'],lv['objects'])
check('A' in active,'held gate lets the courier deliver the replacement box')
check(all(lv['revision']>g.LEVEL_REVISION[i+1] for i,lv in enumerate(g.LEVELS)),'all ten changed layouts invalidate only their stale records')
check(not any(ch in '^~*' for row in g.LEVELS[6]['grid'] for ch in row),'breather stays completely liquid-free')
plate=next(o for o in g.LEVELS[9]['objects'] if o['type']=='plate' and o['channel']=='A')
check(g.plate_surfaces(plate)=={(x,19) for x in range(16,21)},'receiving plate covers every possible delivered-box floor cell')
print('[enrichment-static] 15 fixtures passed')

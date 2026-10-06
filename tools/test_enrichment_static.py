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
# Introduction is a genuine live reciprocal rescue, not a latched solo lever.
lv=g.LEVELS[0]
check({o['channel'] for o in lv['objects'] if o['type']=='plate'}=={'A','B'},'teaching rescue needs both live supports')
check(all(o.get('safe_close') for o in lv['objects'] if o['type']=='door'),'intro gates close safely around waiting partners')
b,v,fs,d=g.build_block_maps(lv['grid'],lv['objects'],'water')
check(not g._can_move(b,v,36,16,41,20,5),'descending jump cannot pass through a solid shelf')
check((47,20) not in g.compute_reach(lv['grid'],lv['objects'],'water',set()),'teaching lower exit is unavailable with all gates closed')
# Freight transportation depends on the actual swept-clear two-point platform.
lv=g.LEVELS[4]; active={'A','B','C'}
reach=g.compute_reach(lv['grid'],lv['objects'],'fire',active)|g.compute_reach(lv['grid'],lv['objects'],'water',active)
box=next(o for o in lv['objects'] if o['type']=='box')
plate=next(o for o in lv['objects'] if o['type']=='plate' and o['channel']=='B')
positions=g.box_reachable(lv['grid'],lv['objects'],box['cell'],reach,active)
check(bool(g.plate_surfaces(plate)&positions),'freight lift can deliver cargo to B')
check(not any(y<=9 for x,y in positions),'cargo cannot climb to the summit without partners')
without=[o for o in lv['objects'] if o['type']!='moving_platform']
check(not (g.plate_surfaces(plate)&g.box_reachable(lv['grid'],without,box['cell'],reach,active)),'removing lifts removes cargo ascent')
blocked=deepcopy(lv);rows=[list(r) for r in blocked['grid']]
for x in range(13,18):rows[22][x]='#'
blocked['grid']=[''.join(r) for r in rows]
check(not (g.plate_surfaces(plate)&g.box_reachable(blocked['grid'],blocked['objects'],box['cell'],reach,active)),'solid obstruction invalidates freight transport')
# Fixed two-way portal pairs and independent keys keep both orders legible.
lv=g.LEVELS[5]
portals=[o for o in lv['objects'] if o['type']=='portal']
check({p['pair'] for p in portals}=={'P1','P2'} and all(sum(p['pair']==pair for p in portals)==2 for pair in ['P1','P2']),'two visible fixed portal pairs provide return loops')
for who,marker in [('fire','E'),('water','Q')]:
    goal=next((row.index(marker),y+1) for y,row in enumerate(lv['grid']) if marker in row)
    check(goal in g.compute_reach(lv['grid'],lv['objects'],who,{'L','R'}),'both independent portal keys release '+who)
    check(all(goal not in g.compute_reach(lv['grid'],lv['objects'],who,{key}) for key in ['L','R']),'neither portal key alone releases '+who)
# The breather's main route never requires a timed keeper, box or hazard crossing.
lv=g.LEVELS[6]
check(not any(o['type'] in ['door','box','delayed_plate'] for o in lv['objects']),'rest-level main path has no mandatory gates or cargo')
for who,marker in [('fire','E'),('water','Q')]:
    goal=next((row.index(marker),y+1) for y,row in enumerate(lv['grid']) if marker in row)
    check(goal in g.compute_reach(lv['grid'],lv['objects'],who,set()),'dry promenade exit is independently reachable by '+who)
# Existing static model must now understand a held-gate box handoff.
lv=g.LEVELS[3];active,_=g.solve_channels(lv['grid'],lv['objects'])
check('A' in active,'held gate lets the courier deliver the replacement box')
check(all(lv['revision']>g.LEVEL_REVISION[i+1] for i,lv in enumerate(g.LEVELS[:10])),'all ten changed layouts invalidate only their stale records')
check(not any(ch in '^~*' for row in g.LEVELS[6]['grid'] for ch in row),'breather stays completely liquid-free')
plate=next(o for o in g.LEVELS[9]['objects'] if o['type']=='plate' and o['channel']=='A')
check(g.plate_surfaces(plate)=={(x,19) for x in range(25,30)},'receiving plate covers every possible delivered-box floor cell')
print('[enrichment-static] all cooperation geometry fixtures passed')

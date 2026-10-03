"""Finite-state relay check: remembers where each actor ended after a gate closes.

The original monotonic switch solver restarts everybody at spawn for every query,
so it cannot model a second keeper beyond a temporary gate. This fallback searches
actual two-actor checkpoint states. It is only enabled for levels without boxes;
box transportation remains under the existing solver plus engine replay coverage.
"""
from collections import deque

def solve(grid, objects, api, limit=30000):
    if any(o.get('type') == 'box' for o in objects):
        return None
    def marker(ch):
        for y,row in enumerate(grid):
            if ch in row:return (row.index(ch), y+1)
    start=(marker('F'),marker('W'),frozenset())
    goals=(marker('E'),marker('Q'))
    plates={cell:o['channel'] for o in objects if o['type']=='plate' for cell in api['plate_surfaces'](o)}
    levers={tuple([*o['cell'][:1],o['cell'][1]+1]):o['channel'] for o in objects if o['type']=='lever'}
    doubles=[([(c[0],c[1]+1) for c in o['cells']],o['channel']) for o in objects if o['type']=='double_plate']
    checkpoints=set(plates)|set(levers)|set(goals)
    for cells,_ in doubles:checkpoints.update(cells)
    cache={}; unions=[set(),set()]
    def reach(who,pos,active):
        key=(who,pos,active)
        if key not in cache:
            b,v,f,d=api['build_block_maps'](grid,objects,('fire','water')[who],active)
            links=api['platform_links'](objects,active)+api['portal_links'](objects)
            cache[key]=api['reachable'](b,v,links,pos,f,d)
        return cache[key]
    queue=deque([start]); seen={start}; parents={}; target=None
    while queue and len(seen)<=limit:
        state=queue.popleft(); f,w,latched=state
        if (f,w)==goals:target=state;break
        for who,pos in enumerate((f,w)):
            other=(w,f)[who]
            powered=latched|({plates[other]} if other in plates else set())
            possible=reach(who,pos,frozenset(powered));unions[who]|=possible
            for dest in checkpoints & possible:
                positions=[f,w];positions[who]=dest
                next_latches=set(latched)
                if dest in levers:next_latches.add(levers[dest])
                for cells,ch in doubles:
                    if len(cells)==2 and set(positions)==set(cells) and positions[0]!=positions[1]:next_latches.add(ch)
                nxt=(positions[0],positions[1],frozenset(next_latches))
                if nxt not in seen:
                    seen.add(nxt);queue.append(nxt);parents[nxt]=state
    if target is None:return None
    history=[];cursor=target
    while cursor!=start:history.append(cursor);cursor=parents[cursor]
    history.reverse()
    return {'active':set(target[2]),'plan':(0,{'fire':set(),'water':set()},unions[0],unions[1]),
            'states':len(seen),'witness':history}

#!/usr/bin/env python3
"""Structural guardrails for the cooperative lift/portal/promenade enrichment."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools'))
import gen_levels

def objects(level, kind):
    return [entry for entry in level['objects'] if entry['type']==kind]

def main():
    l5,l6,l7=gen_levels.LEVELS[4:7]
    assert [level['name'] for level in (l5,l6,l7)] == [
        '5 - 中途接力','6 - 传送终局','7 - 一路同行']
    assert all(level['revision']==3 for level in (l5,l6,l7))
    assert len(objects(l5,'box'))==1
    lifts=objects(l5,'moving_platform')
    assert [lift['channel'] for lift in lifts]==['A','C','B']
    assert lifts[0]['from']==[13,26] and lifts[0]['to']==[13,18]
    assert lifts[0]['width']==5
    cargo=next(p for p in objects(l5,'plate') if p['channel']=='B')
    assert cargo['cell']==[18,18] and cargo['width']==3
    assert objects(l5,'lever')[0]['channel']=='C'
    # Cargo cannot be casually swept sideways from the lower lane into a pool.
    assert all(l5['grid'][25][x]=='#' for x in (5,35,39))
    portals=objects(l6,'portal')
    assert len(portals)==4
    assert {p['pair'] for p in portals}=={'P1','P2'}
    for pair in ('P1','P2'):
        ends=[p['cell'] for p in portals if p['pair']==pair]
        assert len(ends)==2 and ends[0][0]==ends[1][0]
        assert {end[1] for end in ends}=={11,20}
    keys=objects(l6,'double_plate')
    assert {key['channel'] for key in keys}=={'L','R'}
    assert all({cell[1] for cell in key['cells']}=={11,20} for key in keys)
    assert [gate['cell'][0] for gate in objects(l6,'door')]==[50,54]
    assert all(gate['height']==21 for gate in objects(l6,'door'))
    assert not any(ch in '^~*' for row in l7['grid'] for ch in row)
    assert not objects(l7,'door') and not objects(l7,'box')
    assert all(ch=='#' for ch in l7['grid'][20][1:47])
    assert [lift['channel'] for lift in objects(l7,'moving_platform')]==['A','B']
    assert all(lift['to'][1]==11 for lift in objects(l7,'moving_platform'))
    assert any(gem['cell'][1]==7 for gem in objects(l7,'gem'))
    for number,level in ((5,l5),(6,l6),(7,l7)):
        errors=gen_levels.validate(level,number-1)
        assert not any('【致命】' in error for error in errors), errors
        if number!=7: assert not errors,errors
        else: assert len(errors)==2 and all('不用触发任何机关' in error for error in errors)
    print('PASS: L5 cargo/keeper dependencies, L6 fixed paired branch loops, L7 dry optional promenade.')

if __name__=='__main__':main()

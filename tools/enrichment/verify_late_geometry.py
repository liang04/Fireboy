#!/usr/bin/env python3
"""Supplement Input probes with conservative box/branch geometry assertions."""
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_levels as levels


def main():
    l9, l10 = levels.LEVELS[8:10]
    rows = l10['grid']
    objects = l10['objects']
    all_channels = {o['channel'] for o in objects if 'channel' in o}
    # Give the hypothetical pusher every cell, with every gate open. This is a
    # deliberate overestimate; even it cannot raise this gravity-only cargo.
    any_pusher = {(x, y) for y in range(len(rows)) for x in range(len(rows[0]))}
    box = next(o for o in objects if o['type'] == 'box')
    receiver = next(o for o in objects if o['type'] == 'plate' and o['channel'] == 'A')
    from_start = levels.box_reachable(rows, objects, box['cell'], any_pusher, all_channels)
    from_well = levels.box_reachable(rows, objects, receiver['cell'], any_pusher, all_channels)
    assertions = {
        'L10_high_hold_plate_box_inaccessible_even_with_all_gates_open': all((o['cell'][0], o['cell'][1]+1) not in from_start for o in objects if o['type']=='delayed_plate'),
        'L10_box_has_no_upward_route_from_start': all(y >= 12 for x, y in from_start),
        'L10_box_stays_on_well_floor_after_delivery': all(y == 19 for x, y in from_well),
        'L10_delivery_landing_plate_reachable_by_gravity': (receiver['cell'][0], receiver['cell'][1]+1) in from_start,
        'L10_rescue_portals_have_no_channel_requirement': all('channel' not in o for o in objects if o['type'] == 'portal'),
        'L10_both_return_gates_use_persistent_box_weight_A': sum(o['type'] == 'door' and o['channel'] == 'A' for o in objects) == 2,
        'L9_red_repair_is_inside_lava': l9['grid'][20][53] == '^',
        'L9_blue_repair_is_inside_water': l9['grid'][12][53] == '~',
        'L9_upper_tunnel_cannot_be_walked_over': all(l9['grid'][y][x] == '#' for x in range(47, 56) for y in range(11)),
        'L9_lower_tunnel_has_solid_ceiling': all(l9['grid'][18][x] == '#' for x in range(47, 56)),
        'L9_roof_gates_reach_top_boundary': all(o['cell'][1] == 0 and o['height'] == 6 for o in l9['objects'] if o['type'] == 'door' and o['channel'] in ('R','B')),
        'L9_cross_repairs_power_partner_lifts': all(o['channel'] == ('B' if o['from'][0] == 77 else 'R') for o in l9['objects'] if o['type'] == 'moving_platform' and o['from'][0] in [60,77]),
        'L9_two_reversible_roof_routes_have_permanent_decks': any(o['type']=='reversible_route' and {gate['open_state'] for gate in o['gates']}=={0,1} and all(l9['grid'][6][x]=='#' for x in range(63,77)) for o in l9['objects']),
        'L10_high_cooperative_readiness_key_cannot_be_replaced_by_cargo': any(o['type']=='double_plate' and o['channel']=='K' and len(o['cells'])==2 and all((c[0],c[1]+1) not in from_start for c in o['cells']) for o in objects),
        'L10_readiness_gate_blocks_cargo_before_first_stage': any(o['type']=='door' and o['channel']=='K' and o['cell']==[14,7] and o['height']==5 for o in objects),
        'L10_two_rechargeable_stages_have_safe_closing_gates': {o['channel'] for o in objects if o['type']=='delayed_plate'}=={'H','J'} and all(o.get('safe_close') for o in objects if o['type']=='door' and o['channel'] in ['H','J']),
        'L10_full_well_floor_is_covered': levels.plate_surfaces(receiver)=={(x,19) for x in range(len(rows[0])) if rows[18][x]=='.' and rows[19][x]=='#'},
    }
    report = {'assertions': assertions, 'passed': all(assertions.values()),
              'box_start_surfaces': sorted(from_start), 'box_well_surfaces': sorted(from_well),
              'scope': 'Conservative generator geometry checks, supplementary to real Input-only routes; not a physics substitute'}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())

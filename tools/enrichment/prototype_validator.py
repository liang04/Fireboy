"""Geometry upper-bound projection for the two temporal prototype mechanisms.

This projection is deliberately optimistic: timed channels can remain open and
both mutually exclusive bridge states can be explored. It can reject impossible
geometry, but CANNOT prove timing or a legal A/B sequence. The aggregate check
therefore also requires real-engine mechanism tests and immutable input replays.
"""
from copy import deepcopy


def project(grid, objects):
    output, errors, temporal = [], [], False
    height, width = len(grid), len(grid[0])

    def cell_ok(cell):
        return (isinstance(cell, list) and len(cell) == 2 and
                all(isinstance(x, int) for x in cell) and
                0 <= cell[0] < width and 0 <= cell[1] < height)

    for original in objects:
        o = deepcopy(original)
        kind = o.get('type')
        if kind == 'delayed_plate':
            temporal = True
            delay = o.get('delay_seconds', 6.0)
            if not cell_ok(o.get('cell')) or not isinstance(delay, (int, float)) or not 0.1 <= delay <= 60:
                errors.append('【致命】延时开关位置或延时时间无效')
                continue
            if not isinstance(o.get('width', 1), int) or not 1 <= o.get('width', 1) <= width - o['cell'][0]:
                errors.append('【致命】延时开关宽度无效')
            o['type'] = 'lever'
            output.append(o)
        elif kind == 'reversible_route':
            temporal = True
            if o.get('initial_state', 0) not in (0, 1):
                errors.append('【致命】双状态桥路初始状态无效')
            switches, gates = o.get('switches', []), o.get('gates', [])
            if not switches or not gates:
                errors.append('【致命】双状态桥路缺少操作台或通路')
            states = set()
            for gate in gates:
                if not cell_ok(gate.get('cell')) or gate.get('open_state') not in (0, 1) or not isinstance(gate.get('height'), int) or gate['height'] < 1:
                    errors.append('【致命】双状态桥路通路位置/高度/状态无效')
                    continue
                if gate['cell'][1] + gate['height'] > height:
                    errors.append('【致命】双状态桥路门超出地图')
                state = gate['open_state']; states.add(state)
                output.append(dict(type='door', cell=gate['cell'], height=gate['height'],
                                   channel=f"{o.get('channel', 'AB')}_{state}"))
            if states != {0, 1}:
                errors.append('【致命】双状态桥路必须同时提供 A/B 两种通路')
            for switch in switches:
                cell = switch.get('cell') if isinstance(switch, dict) else switch
                if not cell_ok(cell):
                    errors.append('【致命】双状态桥路操作台位置无效'); continue
                if isinstance(switch, dict) and switch.get('select_state', 0) not in (0, 1):
                    errors.append('【致命】双状态桥路选择状态无效')
                for state in (0, 1):
                    output.append(dict(type='lever', cell=cell, channel=f"{o.get('channel', 'AB')}_{state}"))
        else:
            output.append(o)
    return output, errors, temporal

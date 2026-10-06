"""L11: outward elemental forks, cross-powered shortcuts, inward reunion.

The lower wings are element-specific. Each outer lever opens the OTHER
wing's gallery shutter and powers its lift. Both actors can instead take
permanent dry switchback stairs, so an unpowered/missed lift never strands
anyone. The upper K pair latches both reunion gates permanently.
"""


def build(Grid, base):
    g = Grid(64, 24)
    g.border()
    g.row(0, 1, 62, '#')
    g.rect(1, 21, 62, 23, '#')
    g.rect(17, 21, 24, 22, '^')
    g.rect(40, 21, 47, 22, '~')
    # Four-cell clearance above the lower floor is beyond standing jump height.
    # These roofs prevent the central hub from becoming an upper-route bypass.
    g.row(17, 14, 26, '#')
    g.row(17, 38, 50, '#')
    # Permanent galleries: the only holes are the two dry lift shafts.
    g.row(11, 4, 7, '#')
    g.row(11, 11, 52, '#')
    g.row(11, 56, 59, '#')
    # Optional longer recovery routes. Every jump is only two cells up;
    # missed jumps land on a dry outer apron, never in an elemental pool.
    for x1, x2, y in ((3, 6, 19), (1, 3, 17), (4, 6, 15), (1, 3, 13),
                      (57, 60, 19), (60, 62, 17), (57, 59, 15), (60, 62, 13)):
        g.row(y, x1, x2, '#')
    g.put(30, 20, 'F')
    g.put(33, 20, 'W')
    g.put(30, 10, 'E')
    g.put(33, 10, 'Q')
    objects = [
        {'type': 'lever', 'cell': [12, 20], 'channel': 'R'},
        {'type': 'lever', 'cell': [51, 20], 'channel': 'B'},
        {'type': 'moving_platform', 'from': [8, 20], 'to': [8, 11],
         'width': 3, 'speed': 105, 'channel': 'B'},
        {'type': 'moving_platform', 'from': [53, 20], 'to': [53, 11],
         'width': 3, 'speed': 105, 'channel': 'R'},
        # Retract above the map: downward slabs would seal the lower lanes
        # and trap central respawns after the permanent K latch.
        {'type': 'door', 'cell': [19, 0], 'height': 11, 'channel': 'B', 'open_up': True},
        {'type': 'door', 'cell': [44, 0], 'height': 11, 'channel': 'R', 'open_up': True},
        {'type': 'double_plate', 'cells': [[25, 10], [38, 10]], 'channel': 'K'},
        {'type': 'door', 'cell': [27, 0], 'height': 11, 'channel': 'K', 'open_up': True},
        {'type': 'door', 'cell': [36, 0], 'height': 11, 'channel': 'K', 'open_up': True},
    ]
    for x, y in ((21, 22), (12, 20), (15, 10), (24, 10), (30, 10)):
        objects.append({'type': 'gem', 'cell': [x, y], 'color': 'red'})
    for x, y in ((43, 22), (51, 20), (49, 10), (39, 10), (33, 10)):
        objects.append({'type': 'gem', 'cell': [x, y], 'color': 'blue'})
    return {
        'name': '11 - 岔路汇合',
        'subtitle': '从中间分头：火娃向左、水娃向右。拉杆替对方开捷径；错过升降台可走外侧干阶。上层同踩 K，再向中间汇合。',
        # Provisional human target, including communication and a missed lift.
        # Input-only controller and recovery evidence live in tools/new_levels.
        'par_time': 85.0,
        'grid': g.rows(),
        'objects': objects,
        'revision': 1,
    }

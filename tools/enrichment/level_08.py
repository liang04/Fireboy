"""L8: reversible A/B bridge loop, fixed supports and safe remote relay hubs."""
def build(Grid, base):
    g = Grid(50, 23)
    g.border()
    g.rect(1, 20, 48, 22, '#')
    # Two permanent bridge decks. Arch shutters choose access, never the floor.
    g.row(11, 15, 48, '=')
    g.row(20, 15, 48, '=')
    g.row(4, 15, 48, '#')
    # The far bridge landings are separated by the permanent upper deck.
    # Both return through the spacious left stair hub; no dangerous falls.
    for x1, x2, row in ((8, 11, 17), (4, 7, 14), (8, 14, 11)):
        g.row(row, x1, x2, '=')
    g.put(5, 19, 'F'); g.put(7, 19, 'W')
    g.put(1, 19, 'E'); g.put(2, 19, 'Q')
    objects = [{
        'type': 'reversible_route', 'channel': 'AB', 'initial_state': 0,
        'switches': [{'cell': [12, 19]}, {'cell': [12, 10]},
                     {'cell': [44, 19]}, {'cell': [44, 10]}],
        'gates': [{'cell': [26, 5], 'height': 6, 'open_state': 0},
                  {'cell': [26, 12], 'height': 8, 'open_state': 1}],
        'bridges': [{'from': [15, 11], 'to': [48, 11], 'open_state': 0},
                    {'from': [15, 20], 'to': [48, 20], 'open_state': 1}],
    },
        {'type': 'double_plate', 'cells': [[43, 10], [43, 19]], 'channel': 'K'},
        {'type': 'door', 'cell': [3, 1], 'height': 19, 'channel': 'K'},
    ]
    for x, y in ((6, 19), (20, 19), (34, 19), (19, 10), (33, 10)):
        objects.append({'type': 'gem', 'cell': [x, y], 'color': 'red'})
    for x, y in ((8, 19), (18, 19), (32, 19), (21, 10), (35, 10)):
        objects.append({'type': 'gem', 'cell': [x, y], 'color': 'blue'})
    # Both raw-input full-gem orders: 41.65 s / 47.85 s. 90 s allows generous conversation time.
    return dict(base, name='8 - 双桥换路',
                subtitle='A 上桥 / B 下桥：先选一路，远端替队友切换；两人踩 K 开出口，再换路取宝。桥面始终保留。',
                par_time=90.0, grid=g.rows(), objects=objects,
                revision=base.get('revision', 1) + 2)

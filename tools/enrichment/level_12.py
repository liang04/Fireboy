"""L12: a diagonal freight ferry, reversible docks, and a recoverable dry basin.

The two high K pads commission the loading arch; cargo cannot reach them.
A keeper on H moves the ferry while a courier escorts the only crate. A/B
opens the low loading arch OR the high unloading arch, with permanent decks
and consoles on both sides. The delivered crate keeps C powered while BOTH
players ride to the exits. A person holding C cannot make that final trip.

Central freight misses land on a continuous dry catch apron. Only the two
outer wall reclaim pockets use the existing box reset and three-second penalty. Keep cargo on the apron while the empty ferry returns,
then drop it into the low berth to reload. Neither the diagonal
sweep nor the final lift has an overhead ledge or gate intersecting its shaft.
"""


def build(Grid, base):
    g = Grid(54, 23)
    g.border()
    g.row(0, 1, 52, '#')
    g.rect(1, 20, 52, 22, '#')
    # The catch apron is one cell above the low berth: recovered cargo can
    # drop onto a ferry paused near the bottom, rather than climb a tiny lip.
    g.row(19, 19, 52, '#')
    # Only the two outer wall pockets reset lost cargo; the entire central
    # catch apron stays dry and rejoins the berth without a crate-sized step.
    g.put(1, 20, '~')
    g.put(52, 19, '~')
    # The elevated controls cannot be weighted by the freight crate.
    g.row(18, 2, 3, '#')
    g.row(16, 4, 5, '#')
    g.row(14, 6, 11, '#')
    g.row(12, 8, 9, '#')
    # The receiving dock begins beyond the diagonal ferry's rightmost edge.
    g.row(14, 37, 52, '#')
    g.row(12, 40, 42, '#')
    g.row(17, 40, 42, '#')
    g.row(5, 37, 47, '#')
    g.put(4, 19, 'F')
    g.put(7, 19, 'W')
    g.put(40, 4, 'E')
    g.put(45, 4, 'Q')
    objects = [
        {'type': 'box', 'cell': [9, 19]},
        {'type': 'double_plate', 'cells': [[7, 13], [11, 13]], 'channel': 'K'},
        {'type': 'door', 'cell': [12, 14], 'height': 6, 'channel': 'K'},
        {'type': 'plate', 'cell': [9, 11], 'channel': 'H'},
        # A full cell of clearance above the receiving dock makes unloading
        # forgiving: the keeper can pause before the exact turnaround frame.
        {'type': 'moving_platform', 'from': [14, 20], 'to': [32, 13],
         'width': 5, 'speed': 90, 'channel': 'H'},
        {'type': 'reversible_route', 'channel': 'AB', 'initial_state': 0,
         'switches': [{'cell': [11, 19]}, {'cell': [10, 13]},
                      {'cell': [38, 13]}, {'cell': [46, 13]}],
         'gates': [{'cell': [13, 14], 'height': 6, 'open_state': 0},
                   {'cell': [37, 0], 'height': 14, 'open_state': 1}],
         'bridges': [{'from': [10, 20], 'to': [13, 20], 'open_state': 0},
                     {'from': [37, 14], 'to': [41, 14], 'open_state': 1}]},
        # A generous dry receiver keeps the crate useful after over-pushing.
        {'type': 'plate', 'cell': [37, 13], 'width': 16, 'channel': 'C'},
        {'type': 'moving_platform', 'from': [48, 12], 'to': [48, 5],
         'width': 4, 'speed': 90, 'channel': 'C'},
        # Players have an unconditional service route; it never carries cargo.
        {'type': 'portal', 'cell': [41, 16], 'pair': 'R12'},
        {'type': 'portal', 'cell': [41, 11], 'pair': 'R12'},
        {'type': 'gem', 'cell': [7, 13], 'color': 'red'},
        {'type': 'gem', 'cell': [24, 18], 'color': 'red'},
        {'type': 'gem', 'cell': [38, 13], 'color': 'red'},
        {'type': 'gem', 'cell': [40, 4], 'color': 'red'},
        {'type': 'gem', 'cell': [11, 13], 'color': 'blue'},
        {'type': 'gem', 'cell': [34, 18], 'color': 'blue'},
        {'type': 'gem', 'cell': [46, 13], 'color': 'blue'},
        {'type': 'gem', 'cell': [45, 4], 'color': 'blue'},
    ]
    # Provisional human teamwork target, deliberately not a fastest-route claim.
    return {'name': '12 - 合作运输',
            'subtitle': '高台同踩 K 备货；一人守 H、一人护箱斜渡。A 装货、B 卸货；箱留 C 后一起上楼。落箱沿干地推回重装；两端水池复位箱子并加时，R12 接应伙伴。',
            'par_time': 120.0, 'camera_margin': 220.0,
            'grid': g.rows(), 'objects': objects, 'revision': 1}

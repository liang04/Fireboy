"""L13: choose the order of a two-height key and an elemental timed workshop.

The two objectives are genuinely independent. K is a simultaneous west-wing
key. In the east, Water charges H in its pool while Fire enters the lava
workshop and joins Water on the self-latching R key. The dry interior S
lever opens an upper return hatch that either actor can recover, even if
they both entered H early. There are no portals or reversible bridges.
"""


def build(Grid, base):
    g = Grid(70, 25)
    g.border()
    g.row(0, 1, 68, '#')
    g.rect(1, 21, 68, 24, '#')
    # West: a generous switchback stair, with a permanent dry catch floor.
    # Both plates are needed at once; one person cannot run between them.
    g.rect(3, 11, 17, 13, '#')
    for left, right, row in ((22, 25, 19), (18, 21, 17),
                             (22, 25, 15), (18, 21, 13)):
        g.row(row, left, right, '#')
    # East: Water alone can keep the submerged H relay charged. Fire alone
    # can reach the inner R key in the long low-roofed lava workshop.
    g.rect(28, 21, 30, 22, '~')
    g.rect(48, 21, 55, 22, '^')
    g.rect(48, 18, 55, 19, '#')
    # The sealed vertical partition has a timed lower doorway and an S-keyed
    # upper return hatch. Both approaches have permanent stairs and landings.
    g.row(13, 41, 45, '#')
    for left, right, row in ((37, 40, 19), (33, 36, 17),
                             (37, 40, 15), (56, 58, 19),
                             (53, 56, 17), (49, 52, 15), (45, 48, 13)):
        g.row(row, left, right, '#')
    g.put(26, 20, 'F')
    g.put(31, 20, 'W')
    g.put(65, 20, 'E')
    g.put(67, 20, 'Q')
    objects = [
        {'type': 'double_plate', 'cells': [[6, 20], [8, 10]], 'channel': 'K'},
        {'type': 'door', 'cell': [60, 0], 'height': 21, 'channel': 'K'},
        {'type': 'delayed_plate', 'cell': [29, 22], 'channel': 'H',
         'delay_seconds': 6.0},
        {'type': 'door', 'cell': [43, 14], 'height': 7, 'channel': 'H',
         'safe_close': True},
        {'type': 'double_plate', 'cells': [[53, 22], [41, 20]], 'channel': 'R'},
        {'type': 'lever', 'cell': [46, 20], 'channel': 'S'},
        {'type': 'door', 'cell': [43, 0], 'height': 13, 'channel': 'S',
         'open_up': True, 'safe_close': True},
        {'type': 'door', 'cell': [62, 0], 'height': 21, 'channel': 'R'},
        {'type': 'gem', 'cell': [6, 20], 'color': 'red'},
        {'type': 'gem', 'cell': [39, 20], 'color': 'red'},
        {'type': 'gem', 'cell': [52, 22], 'color': 'red'},
        {'type': 'gem', 'cell': [65, 20], 'color': 'red'},
        {'type': 'gem', 'cell': [8, 10], 'color': 'blue'},
        {'type': 'gem', 'cell': [29, 22], 'color': 'blue'},
        {'type': 'gem', 'cell': [51, 14], 'color': 'blue'},
        {'type': 'gem', 'cell': [67, 20], 'color': 'blue'},
    ]
    # A generous first-play target; both objective orders have input-only
    # completion fixtures. Human co-op calibration remains a separate task.
    return dict(base, name='13 - 综合挑战·自由排程',
                subtitle='任选先后：西翼高低同踩 K；东翼水娃充 H、火娃潜入，水娃接班同踩 R。门内 S 开上层退路，超时可重充；K/R 齐了再会合。',
                par_time=110.0, camera_margin=240.0,
                grid=g.rows(), objects=objects, revision=1)

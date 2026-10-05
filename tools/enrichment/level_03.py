"""L3: elemental split, then choose a reversible cross-route treasure loop.

C/D/E still teach the original relay. The dry stairs beyond E let Watergirl
return to Fireboy's upper route while Fireboy takes the lower route. For all
collectibles, Watergirl holds D for Fireboy, then Fireboy holds C for Watergirl:
the same two live supports have different keepers on the second visit.
"""
def build(Grid, base):
    g = Grid(68, 24)
    for y, row in enumerate(base['grid']):
        for x, ch in enumerate(row):
            if x == 63: continue
            g.put(x, y, '.' if ch in 'EQ' else ch)
    g.border()
    g.rect(1,21,66,23,'#')
    g.rect(18,21,25,22,'~')
    # The vault has a solid roof; dropping off the upper route cannot bypass V.
    g.row(17,61,66,'#')
    # A dry, reversible switchback uses the vault roof as its middle landing.
    # No new gate is added, and every missed jump lands on safe ground.
    g.row(19,58,60,'#')
    g.row(15,58,60,'#')
    g.put(57,20,'E'); g.put(59,20,'Q')
    objects = [o.copy() for o in base['objects'] if not (o.get('channel') == 'E')]
    objects += [
        {'type':'plate','cell':[51,11],'channel':'D'},
        {'type':'door','cell':[54,14],'height':7,'channel':'D'},
        {'type':'lever','cell':[58,20],'channel':'E'},
        {'type':'door','cell':[54,6],'height':6,'channel':'E'},
        {'type':'double_plate','cells':[[55,11],[57,20]],'channel':'V'},
        {'type':'door','cell':[61,18],'height':3,'channel':'V'},
        {'type':'gem','cell':[63,20],'color':'red'},
        {'type':'gem','cell':[65,20],'color':'blue'},
        # Optional cross-route gems: both are on the other actor's old lane.
        {'type':'gem','cell':[42,20],'color':'red'},
        {'type':'gem','cell':[44,11],'color':'blue'},
    ]
    # Input-only all-gem proof: 31.50 s; 65 s leaves 33.50 s for human
    # reading, communication, stair recovery and deciding the optional order.
    # Prior enrichment was base + 1; this prototype advances that exactly once.
    return dict(base, subtitle='先分头接力 C、D、E。可直接会合，或从右侧干阶换路：水娃守 D、火娃守 C，互助收齐异路宝石；V 开宝库。',
                grid=g.rows(), objects=objects, revision=base['revision']+2, par_time=65.0)

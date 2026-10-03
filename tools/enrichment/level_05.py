"""L5: reciprocal lift escort, safe interchange, optional gem balcony."""
def build(Grid, base):
    g = Grid(48, 29)
    g.border()
    g.rect(1, 26, 46, 28, '#')
    g.rect(13, 26, 15, 27, '^')
    g.rect(33, 26, 35, 27, '~')
    g.row(16, 8, 39, '#')
    g.row(13, 21, 24, '=')
    g.row(5, 8, 39, '#')
    g.put(3, 25, 'F'); g.put(28, 25, 'W')
    g.put(21, 4, 'E'); g.put(26, 4, 'Q')
    objects = [
        {'type':'plate', 'cell':[24,25], 'channel':'A'},
        {'type':'moving_platform', 'from':[4,24], 'to':[4,16], 'width':4, 'speed':145, 'channel':'A'},
        {'type':'lever', 'cell':[10,15], 'channel':'B'},
        {'type':'moving_platform', 'from':[40,24], 'to':[40,16], 'width':4, 'speed':145, 'channel':'B'},
        {'type':'plate', 'cell':[34,15], 'channel':'C'},
        {'type':'moving_platform', 'from':[4,14], 'to':[4,5], 'width':4, 'speed':145, 'channel':'C'},
        {'type':'lever', 'cell':[11,4], 'channel':'D'},
        {'type':'moving_platform', 'from':[40,14], 'to':[40,5], 'width':4, 'speed':145, 'channel':'D'},
        {'type':'gem', 'cell':[13,27], 'color':'red'},
        {'type':'gem', 'cell':[15,27], 'color':'red'},
        {'type':'gem', 'cell':[21,12], 'color':'red'},
        {'type':'gem', 'cell':[17,4], 'color':'red'},
        {'type':'gem', 'cell':[33,27], 'color':'blue'},
        {'type':'gem', 'cell':[35,27], 'color':'blue'},
        {'type':'gem', 'cell':[24,12], 'color':'blue'},
        {'type':'gem', 'cell':[33,4], 'color':'blue'},
    ]
    # Provisional human target: 35.25 s tested input route × 1.5 + 10 s decisions, rounded up to 65 s.
    # Automated route evidence establishes feasibility, not human playtest balance.
    return dict(base, name='5 - 中途接力', subtitle='先护送伙伴到中层，再交换供电；中层可以安全重整，错过电梯就等下一班。顶层一起汇合。', par_time=65.0, grid=g.rows(), objects=objects, revision=base.get('revision',1)+1)

"""L5: a freight lift, a scout's return lift, and a cargo-powered summit."""
def build(Grid, base):
    g = Grid(54, 29)
    g.border()
    g.rect(1, 26, 52, 28, '#')
    g.rect(2, 26, 4, 27, '^')
    g.rect(36, 26, 38, 27, '~')
    g.row(19, 18, 45, '#')
    g.row(9, 18, 45, '#')
    g.row(6, 27, 31, '=')
    g.put(5,25,'#'); g.put(35,25,'#'); g.put(39,25,'#')
    g.put(6, 25, 'F'); g.put(30, 25, 'W')
    g.put(33, 8, 'E'); g.put(39, 8, 'Q')
    objects = [
        # A carries both scout and cargo. Unload first, or scout ahead to enable C.
        # Releasing
        # it pauses the existing two-point platform; stepping back on resumes it.
        {'type':'plate', 'cell':[32,25], 'channel':'A'},
        {'type':'box', 'cell':[10,25]},
        {'type':'moving_platform', 'from':[13,26], 'to':[13,18], 'width':5, 'speed':90, 'channel':'A'},
        # The first visitor can enable an independent way up for the operator.
        {'type':'lever', 'cell':[22,18], 'channel':'C'},
        {'type':'moving_platform', 'from':[46,24], 'to':[46,19], 'width':4, 'speed':120, 'channel':'C'},
        # A person can test B, but the delivered box frees BOTH partners for the
        # final journey. Wide landing prevents a small nudge losing the supply.
        {'type':'plate', 'cell':[18,18], 'width':3, 'channel':'B'},
        {'type':'moving_platform', 'from':[46,17], 'to':[46,9], 'width':4, 'speed':100, 'channel':'B'},
        {'type':'gem', 'cell':[3,27], 'color':'red'},
        {'type':'gem', 'cell':[24,18], 'color':'red'},
        {'type':'gem', 'cell':[28,5], 'color':'red'},
        {'type':'gem', 'cell':[33,8], 'color':'red'},
        {'type':'gem', 'cell':[37,27], 'color':'blue'},
        {'type':'gem', 'cell':[35,18], 'color':'blue'},
        {'type':'gem', 'cell':[30,5], 'color':'blue'},
        {'type':'gem', 'cell':[39,8], 'color':'blue'},
    ]
    return dict(base, name='5 - 中途接力',
        subtitle='A 货梯先卸箱，或先上楼拉 C 接应；把箱子留在 B，二人再去山顶。松开 A 只会暂停。',
        par_time=100.0, grid=g.rows(), objects=objects, revision=base.get('revision',1)+2)

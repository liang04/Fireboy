"""L8: short alternating remote relays, then a simultaneous final launch."""
def build(Grid, base):
    g = Grid(62, 33)
    g.border()
    g.rect(1,30,60,32,'#')
    g.rect(26,30,33,31,'*')
    for row in (22,14,5):
        g.row(row,10,18,'#')
        g.row(row,42,50,'#')
    g.put(4,29,'F'); g.put(56,29,'W')
    g.put(14,4,'E'); g.put(46,4,'Q')
    objects = [
        {'type':'lever','cell':[23,29],'channel':'R1'},
        {'type':'moving_platform','from':[39,28],'to':[39,22],'width':3,'speed':155,'channel':'R1'},
        {'type':'lever','cell':[45,21],'channel':'L1'},
        {'type':'moving_platform','from':[19,28],'to':[19,22],'width':3,'speed':155,'channel':'L1'},
        {'type':'lever','cell':[13,21],'channel':'R2'},
        {'type':'moving_platform','from':[39,20],'to':[39,14],'width':3,'speed':155,'channel':'R2'},
        {'type':'lever','cell':[43,13],'channel':'L2'},
        {'type':'moving_platform','from':[19,20],'to':[19,14],'width':3,'speed':155,'channel':'L2'},
        {'type':'double_plate','cells':[[13,13],[46,13]],'channel':'T'},
        {'type':'moving_platform','from':[19,12],'to':[19,5],'width':3,'speed':155,'channel':'T'},
        {'type':'moving_platform','from':[39,12],'to':[39,5],'width':3,'speed':155,'channel':'T'},
    ]
    for x,y in ((8,29),(23,29),(14,21),(17,13),(12,4)):
        objects.append({'type':'gem','cell':[x,y],'color':'red'})
    for x,y in ((54,29),(36,29),(48,21),(47,13),(49,4)):
        objects.append({'type':'gem','cell':[x,y],'color':'blue'})
    # Provisional human target: 29.6833 s tested input route × 1.5 + 10 s decisions, rounded up to 55 s.
    # Automated route evidence establishes feasibility, not human playtest balance.
    return dict(base, name='8 - 遥供接力塔', subtitle='隔岸交替供电，逐层接棒；第二中层两人同时踩亮 T，再各自登顶。错过电梯可以等它返回。', par_time=55.0, grid=g.rows(), objects=objects, revision=base.get('revision',1)+1)

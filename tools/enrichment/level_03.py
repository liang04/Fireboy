"""Two relay rounds, exchange the keeper, then an optional shared vault."""
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
    g.rect(61,16,66,17,'#')
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
    ]
    return dict(base, subtitle='先水娃守 C，后火娃守 D；水娃打开 E 后在庭院会合。上下同时踩 V 可开宝库。',
                grid=g.rows(), objects=objects, revision=base['revision']+1, par_time=35.0)

"""L6: two fixed portal branches, independent shared keys and a visible hub loop."""
def build(Grid, base):
    g = Grid(62, 25)
    g.border(); g.rect(1,21,60,24,'#')
    g.rect(4,12,22,14,'#'); g.rect(28,12,46,14,'#')
    g.rect(15,12,17,13,'^'); g.rect(36,12,38,13,'~')
    g.put(9,20,'F'); g.put(40,20,'W')
    g.put(57,20,'E'); g.put(59,20,'Q')
    objects = [
        {'type':'portal','cell':[6,20],'pair':'P1'},
        {'type':'portal','cell':[6,11],'pair':'P1'},
        {'type':'portal','cell':[44,20],'pair':'P2'},
        {'type':'portal','cell':[44,11],'pair':'P2'},
        # Neither key is a solo round-trip: the hub keeper and branch scout
        # must stand together. Once lit, either branch can be revisited freely.
        {'type':'double_plate','cells':[[20,11],[16,20]],'channel':'L'},
        {'type':'double_plate','cells':[[30,11],[34,20]],'channel':'R'},
        {'type':'door','cell':[50,0],'height':21,'channel':'L'},
        {'type':'door','cell':[54,0],'height':21,'channel':'R'},
        {'type':'gem','cell':[9,20],'color':'red'},
        {'type':'gem','cell':[10,11],'color':'red'},
        {'type':'gem','cell':[16,13],'color':'red'},
        {'type':'gem','cell':[31,11],'color':'red'},
        {'type':'gem','cell':[40,20],'color':'blue'},
        {'type':'gem','cell':[41,11],'color':'blue'},
        {'type':'gem','cell':[37,13],'color':'blue'},
        {'type':'gem','cell':[21,11],'color':'blue'},
    ]
    return dict(base, name='6 - 传送终局', grid=g.rows(), objects=objects,
        revision=base.get('revision',1)+2,
        subtitle='P1 左台、P2 右台，原门原路返回。任选顺序：一人在台上、一人在下方同踩 L / R；两钥匙亮后换路取宝、会合。',
        par_time=100.0)

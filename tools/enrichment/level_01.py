"""Short elemental lesson followed by a short reciprocal live-support rescue."""
def build(Grid, base):
    g=Grid(54,23);g.border();g.rect(1,20,52,22,'#')
    g.rect(12,20,14,21,'^');g.rect(28,20,30,21,'~')
    g.row(18,32,33,'#');g.row(16,34,50,'#');g.row(17,34,50,'#')
    g.row(16,37,44,'^')
    g.put(52,18,'#')  # A missed jump drops onto safe ground; step back to the bridge.
    g.put(3,19,'F');g.put(6,19,'W');g.put(50,15,'E');g.put(47,19,'Q')
    objects=[
        {'type':'plate','cell':[46,15],'channel':'A'},
        {'type':'door','cell':[36,18],'height':2,'channel':'A','safe_close':True},
        {'type':'plate','cell':[42,19],'channel':'B'},
        {'type':'door','cell':[49,10],'height':6,'channel':'B','safe_close':True,'open_up':True},
        {'type':'gem','cell':[12,21],'color':'red'},
        {'type':'gem','cell':[14,21],'color':'red'},
        {'type':'gem','cell':[39,16],'color':'red'},
        {'type':'gem','cell':[28,21],'color':'blue'},
        {'type':'gem','cell':[30,21],'color':'blue'},
        {'type':'gem','cell':[43,19],'color':'blue'},
    ]
    return dict(base,grid=g.rows(),objects=objects,revision=base['revision']+2,
        subtitle='先认识浅池。火娃守 A 接水娃过下门；水娃踩住 B，等火娃进出口再松手。失误可回头重试。',par_time=40.0)

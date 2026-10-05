"""One crate, two jobs: first release a scout, then weight the onward gate.

A live keeper first admits the crate through the low A barrier. The scout opens the permanent upper return shortcut before the courier removes
B's crate. Removing it closes only the lower arch; the upper bridge is solid and
reversible. The crate stays in a wide, dry floor-level bay for both deliveries.
"""
def build(Grid, base):
    g = Grid(56, 24); g.border()
    g.rect(1,22,54,23,'#')
    g.row(15,12,23,'#')
    # Both ends have forgiving stairs; a miss lands back in the dry crate bay.
    for x0,x1,y in ((6,8,20),(8,10,18),(10,11,16),
                     (27,29,20),(25,27,18),(24,26,16)):
        g.row(y,x0,x1,'#')
    g.row(22,33,39,'*'); g.row(22,45,47,'~')
    g.row(21,50,54,'#'); g.row(20,52,54,'#')
    g.put(3,21,'F');g.put(5,21,'W');g.put(54,19,'E');g.put(51,20,'Q')
    objects=[
        {'type':'box','cell':[10,21]},
        {'type':'plate','cell':[4,21],'channel':'A'},
        {'type':'door','cell':[12,20],'height':2,'channel':'A','safe_close':True},
        {'type':'plate','cell':[14,21],'channel':'B'},
        {'type':'door','cell':[18,15],'height':7,'channel':'B','safe_close':True},
        {'type':'lever','cell':[22,14],'channel':'C'},
        {'type':'door','cell':[18,5],'height':10,'channel':'C','open_up':True,'safe_close':True},
        {'type':'plate','cell':[16,21],'channel':'D'},
        {'type':'door','cell':[32,14],'height':8,'channel':'D','safe_close':True},
        {'type':'moving_platform','from':[31,20],'to':[40,20],'width':3,'speed':95},
        {'type':'gem','cell':[14,20],'color':'red'},
        {'type':'gem','cell':[20,14],'color':'red'},
        {'type':'gem','cell':[53,19],'color':'red'},
        {'type':'gem','cell':[22,14],'color':'blue'},
        {'type':'gem','cell':[46,22],'color':'blue'},
        {'type':'gem','cell':[51,20],'color':'blue'},
    ]
    return dict(base,name='2 - 哨台交接',subtitle='队友守 A 送箱压 B，再过门上楼拉 C 开回程桥；把同一木箱推到 D，两人经 C 会合渡池。',par_time=70.0,revision=base['revision']+2,grid=g.rows(),objects=objects)

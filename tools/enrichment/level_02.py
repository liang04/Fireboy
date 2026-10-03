"""Guard-post handoff: one holds A, the other delivers the shared weight to B."""
def build(Grid, base):
    g = Grid(52, 24); g.border()
    g.rect(1, 22, 50, 23, '#')
    g.row(22, 25, 32, '*'); g.row(22, 39, 41, '~')
    g.row(21, 45, 50, '#'); g.row(20, 48, 50, '#')
    # The guard post cannot reach the right-hand drop until the delivered box
    # opens B. Its sinking gate is behind the courier when B becomes active.
    g.row(17, 12, 20, '=')
    g.put(3,21,'F'); g.put(6,21,'W'); g.put(50,19,'E'); g.put(46,20,'Q')
    objects = [
        {'type':'box','cell':[10,21]},
        {'type':'plate','cell':[15,16],'channel':'A'},
        {'type':'door','cell':[18,17],'height':5,'channel':'A'},
        {'type':'plate','cell':[22,21],'channel':'B'},
        {'type':'door','cell':[19,10],'height':7,'channel':'B'},
        {'type':'door','cell':[24,15],'height':7,'channel':'B'},
        {'type':'moving_platform','from':[22,20],'to':[33,20],'width':3,'speed':95},
        {'type':'lever','cell':[35,21],'channel':'C'},
        {'type':'door','cell':[37,15],'height':7,'channel':'C'},
        {'type':'portal','cell':[2,21],'pair':'V1'},
        {'type':'portal','cell':[14,16],'pair':'V1'},
        {'type':'gem','cell':[10,20],'color':'red'},
        {'type':'gem','cell':[34,21],'color':'red'},
        {'type':'gem','cell':[49,19],'color':'red'},
        {'type':'gem','cell':[15,16],'color':'blue'},
        {'type':'gem','cell':[39,22],'color':'blue'},
        {'type':'gem','cell':[47,20],'color':'blue'},
    ]
    return {'name':'2 - 哨台交接','subtitle':'一人传送上哨台守住 A；另一人送箱压 B，接应同伴下来，再一起渡池。','par_time':45.0,'revision':base['revision']+1,'grid':g.rows(),'objects':objects}
